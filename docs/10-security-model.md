# 10 — Security Model

Planning only. No security mechanism is implemented in Phase 0–1; this defines shapes and rules so later phases don't improvise.

## Core decision

> **Navesti does not own persistent credential storage.** The host application stores credentials and supplies them; Navesti uses them for the duration of a call and forgets them.

Navesti may define **credential shapes** (frozen value objects describing what a connector needs):

```
Navesti::Credentials (per dialect/auth profile)
  client_id
  client_secret reference        # reference/handle, host resolves to the secret
  transport certificate reference
  signing key reference
  kid
  token endpoint
  jwks endpoint
```

"Reference" is deliberate: where possible the host passes a handle that resolves to key material (or an in-memory key object), so secrets traverse the fewest layers. The dialect's auth profile declares *which* of these fields it requires; constructing an adapter with missing credential fields fails loudly at construction time.

## Rules

1. **No raw credentials in Navesti logs.** Ever. Includes tokens, secrets, signatures, full `Authorization` headers.
2. **Credential object passed in by host** at adapter construction or per call. Navesti holds them in memory only.
3. **Redaction rules:** any logging/inspection surface (`#inspect`, error messages, raised exceptions) on credential-bearing objects must redact secret fields by construction (`#<Navesti::Credentials client_id=... client_secret=[REDACTED]>`). Errors that embed HTTP requests must strip auth headers. This is conformance-tested.
4. **Test fixture rules:** fixtures use obviously fake values (`client_id: "test-client"`, IBANs from the official test ranges, certificates generated for tests). No copied sandbox credentials — *note: an LHV sandbox client cert/key pair exists in this repo's old `navesti_lhv` branch history; do not carry that pattern forward, and consider purging/rotating it.*
5. **Raw evidence vs. redaction:** evidence returned to the host is unredacted (the host's persistence is its own trust domain and may include bank-signed payloads needed for audit). Redaction applies to *logs and error surfaces*, which travel further than evidence.

## LHV Phase 1 security surface (decided)

LHV's API uses the eIDAS **QWAC** transport certificate for TPP identification; **QSEAL is not required or supported**, and the PSD2 ID is read from Subject OID `2.5.4.97`. So LHV Phase 1 needs only:

- **mTLS** (QWAC client cert + key) on the transport.
- **`X-Request-ID`** (UUID) per call.
- **Bearer token** on AIS/PIS calls.
- **Secret redaction** in logs and errors.
- **No request-body signing** — no JWS/QSEAL for LHV. Do not overbuild it for this bank.

Key handling (accepted): private keys are **local files referenced by path** (`LHV_CLIENT_CERT_PATH`, `LHV_CLIENT_KEY_PATH`, `LHV_CA_CHAIN_PATH`, `LHV_TPP_ID`); `certs/`, `*.key`, `*.crt`, `*.pem`, `.env` are gitignored. **No certs/keys in git, docs, fixtures, logs, or errors.** Error text may say `client key file missing` or `client certificate invalid`, but must **not** print absolute key paths that could reveal workstation structure (e.g. `failed loading /Users/.../secret.key`) outside an explicit debug mode.

> Future banks may require QSEAL/JWS signing. The signing seam stays deferred (below); LHV does not need it, so it is not built yet.

## Link following, path building, and token evidence (hardening)

From the PR-#5 review and a follow-up review, these boundary rules hold:

1. **Origin + API-root pinned link handling.** Every bank-supplied actionable link — `balances_href` (followed server-side), and `scaRedirect` / `status` / `authorisation_url` (returned to the host/browser) — is resolved through `Config#absolute`, pinned to the configured origin **and** the PSD2 root path: a leading-slash path resolves against root; any URL is allowed only if its scheme/host/port match root and its path is under root's path (e.g. `/psd2`); `..` traversal, protocol-relative, off-origin, look-alike host, userinfo smuggling, scheme downgrade, and same-origin-but-outside-root all fail. This stops a tampered link from (a) redirecting a credentialed (mTLS + `Bearer` + `Consent-ID`) request off-origin — **access-token exfiltration / SSRF** (the private key is never transmitted) — or (b) sending the PSU's browser to a **phishing** page. For *followed* links, validation failure raises `UnsafeUrlError` before any request. For *returned* SCA links, the unsafe link is **dropped** (interaction omitted) but the submission is still returned — an already-initiated payment is never discarded over a bad link; the host falls back to status polling. The offending URL is never echoed (it may carry a token).
2. **Path-segment encoding.** Caller/provider ids interpolated into URL paths (`account_id`, `payment_id`) are percent-encoded per segment, so a `/`, `?`, `#`, or traversal-like id cannot change the addressed path or inject a query.
3. **Redacted token evidence and `to_h`.** Most provider bodies are non-secret and kept verbatim. The OAuth token response is the exception — its body *is* the secret — so `Token#raw` stores **redacted** evidence (`evidence(response, redact: true)`). Additionally `Token#to_h` (the log/serialize/job-arg surface) masks `access_token`/`refresh_token`; the real values are reachable only via the typed readers and the deliberately-named `Token#to_secret_h`.
4. **Conservative transport classification.** The HTTP client maps every transport exception to a typed `TransportError` with `side_effect_possible` set conservatively: `false` only for provably-before-send failures (TLS handshake, connect timeout, `ECONNREFUSED`, DNS); `true` for any after-write or ambiguous failure (`ReadTimeout`/`WriteTimeout`, `EOFError`, `ECONNRESET`/`EPIPE` via `SystemCallError`, `IOError`, `Net::HTTPBadResponse`). This is the PIS retry-safety contract — an ambiguous network failure on a payment never reads as "safe to retry." Messages carry the exception class only, never a raw message that could contain a URL.
5. **Deep-frozen evidence.** Value objects recursively freeze nested `raw` payloads, so preserved evidence is immutable after construction (audit integrity), not just frozen at the top level.
6. **Idempotency is correlation, not a guarantee.** LHV's JSON SEPA API documents no idempotency mechanism. When the host supplies `idempotency_key`, Navesti derives a deterministic (RFC-4122 v5) `X-Request-ID` for payment initiation so retries correlate — but the host MUST reconcile via payment status after an ambiguous outcome before retrying (the double-send axis). Deterministic local SEPA validation (`Dialect.validate_payment_order!`: EUR-for-SEPA, name ≤ 70, remittance ≤ 140) rejects predictable errors before dialing.

## Deferred mechanics (interfaces sketched later, implemented when a real bank forces them)

| Mechanism | When | Notes |
|---|---|---|
| OAuth2 client_credentials + auth-code exchange | Phase 4 (first real AIS) | Navesti exposes `exchange`/`refresh` *calls*; the host owns token storage and refresh scheduling (open question 5) |
| mTLS transport (QWAC-style client certs) | Phase 4 | cert/key supplied per adapter; HTTP abstraction must accept them from day one of Phase 1 so the seam exists |
| JWS/JWT request signing (QSealC-style) | Phase 4–5 | per-dialect declaration of what gets signed |
| HMAC webhook verification | Phase 5 | interface defined in [09-webhooks.md](09-webhooks.md) |

## Threats considered (and who owns them)

- Credential leakage via logs/errors → Navesti (redaction by construction).
- Forged webhooks → Navesti verifies signatures; Sorbet-Core decides policy on failures.
- Replayed webhooks → Sorbet-Core (dedup on event_id + fingerprint).
- Token theft at rest → host (storage is theirs).
- Certificate isolation (one tenant's certs vs another's) → host today; this is the named trigger that could force the gem→service decision in Phase 7 (ADR would be required).
