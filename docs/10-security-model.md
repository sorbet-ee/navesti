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

From the PR-#5 review, three boundary rules now hold:

1. **Same-origin link following.** HATEOAS links (e.g. `account._links.balances.href`) are resolved through `Config#absolute`, which is **pinned to the configured origin**: a leading-slash path resolves against root; an absolute URL is allowed only if its scheme/host/port match root; anything else (off-origin, look-alike host, userinfo smuggling, scheme downgrade, protocol-relative) raises `Navesti::UnsafeUrlError` **before any request is sent**. This stops a bank-supplied or tampered link from redirecting a credentialed (mTLS + `Bearer` + `Consent-ID`) request to another host — the real harm being **access-token exfiltration / SSRF**, not private-key exposure (the key is never transmitted). Any future followed link (e.g. decoupled `authorisation_url`) must use the same guard. The offending URL is never echoed in the error (it may carry a token).
2. **Path-segment encoding.** Caller/provider ids interpolated into URL paths (`account_id`, `payment_id`) are percent-encoded per segment, so a `/`, `?`, `#`, or traversal-like id cannot change the addressed path or inject a query. Encoding keeps everything on-origin.
3. **Redacted token evidence.** Most provider bodies are non-secret and kept verbatim as raw evidence. The OAuth token response is the exception — its body *is* the secret — so `Token#raw` stores **redacted** evidence (`evidence(response, redact: true)` scrubs `access_token`/`refresh_token`). The typed `access_token` field still carries the real value for the host; the evidence blob, which reads as "safe to persist," does not duplicate it.

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
