# LHV — Swagger & API Notes

**Swagger is verification evidence, not a code-generation source.** We read it to confirm paths and schemas and to copy representative samples into fixtures. We do **not** generate a fat client, vendor generated code, or let Swagger dictate Navesti's domain model. The dialect remains ours.

- Sandbox Swagger UI: `https://api.sandbox.lhv.eu/psd2/swagger-ui/index.html?configUrl=/psd2/documentation/api-docs/swagger-config`
- Sandbox is free, requires no licence, and is technically similar to live. Usable directly in Swagger or from a developed client / Postman.

## Environments

| | Root | Notes |
|---|---|---|
| Sandbox | `https://api.sandbox.lhv.eu/psd2` | test certs, free |
| Live | `https://api.lhv.eu/psd2` | requires licence + production QWAC |

Version is **per-service**, not a single base segment: OAuth has no version, AIS is `/v1`, PIS JSON is `/v1.1`.

```
{root}/oauth/authorize | /oauth/token | /oauth/revoke      (no version)
{root}/v1/tpp-verification
{root}/v1/accounts-list                                    (no-consent AIS)
{root}/v1/accounts/{id}/balances                           (consent-gated AIS)
{root}/v1.1/payments/sepa-credit-transfers (+ /{id}/status)
```

## Implemented endpoints

Phase 1:

| Purpose | Method & path | Notes |
|---|---|---|
| TPP verification | `GET /v1/tpp-verification` | `X-Request-ID` required; returns access + tppId + name + roles |
| OAuth authorize (URL only) | `GET /oauth/authorize` | `scope=psd2`, `response_type=code`, `client_id=<tpp_id>`, `redirect_uri`, `state` |
| OAuth token | `POST /oauth/token` | form-encoded; `client_id`, `grant_type=authorization_code`, `code`, `redirect_uri` |
| AIS accounts-list | `GET /v1/accounts-list` | no consent; `Authorization: Bearer`; `onlyActive`; optional `PSU-Corporate-ID` |
| PIS SEPA init | `POST /v1.1/payments/sepa-credit-transfers` | `Bearer`; `TPP-Redirect-Preferred`, `TPP-Redirect-URI`, optional `TPP-Nok-Redirect-URI` |
| PIS status | `GET /v1.1/payments/sepa-credit-transfers/{paymentId}/status` | `Bearer`; returns `transactionStatus` |

Phase LHV-2A:

| Purpose | Method & path | Notes |
|---|---|---|
| AIS Read Balances | `GET /v1/accounts/{resourceId}/balances` | **consent-gated**: `Bearer` + `Consent-ID` (host-supplied); optional `PSU-Corporate-ID`. Returns Berlin Group typed `balances[]` (`interimAvailable`, `closingBooked`, …). Prefer the `_links.balances.href` from accounts-list. |
| OAuth token refresh | `POST /oauth/token` | form-encoded; `client_id`, `grant_type=refresh_token`, `refresh_token` (no `redirect_uri`) |

Phase LHV-2B:

| Purpose | Method & path | Notes |
|---|---|---|
| Payment cancellation | `DELETE /v1.1/payments/sepa-credit-transfers/{paymentId}/cancel` | `Bearer`. Valid only pre-SCA; success → CANC / synthesized cancelled (no side effect). Post-SCA → bank rejects (raises). |
| OAuth token revoke | `POST /oauth/revoke` | form-encoded; `client_id`, `token`, optional `token_type_hint`. Idempotent (200 even for nonexistent token). |
| Decoupled SCA **discovery** | (read-only, from the init response) | `scaMethods[]` + `_links.startAuthorisationWithAuthenticationMethodSelection` surfaced on `PaymentSubmission`; the flow is not started. |

## Deferred endpoints (later)

Decoupled SCA **execution** (`POST …/authorisations` + `GET …/authorisations/{id}`), consent **creation** (`POST /v1/consents`, `…/authorisations`), accounts-with-consent (`POST /v1/accounts`), transactions, PIIS (confirmation of funds), XML payments (`/v1/payments/pain.001-credit-transfers`), periodic payments.

## Known discrepancies & findings

- **`RCVD` vs `RVCD`** — the sample JSON initiation response shows `transactionStatus: "RCVD"`, while the status table lists `RVCD` for "validated, ready for SCA". Treat both as the same semantic state (`requires_authorization`, pre-SCA, `side_effect_possible: false`) and **preserve the raw value**.
- **Account currency `"XXX"`** — accounts are multi-currency; accounts-list reports `currency: "XXX"`. `Account.currency` is provider-reported and must not be ISO-validated. Real currency lives in Balance (deferred). See [../../02-domain-model.md](../../02-domain-model.md).
- **Security: QWAC only** — eIDAS QWAC transport cert identifies the TPP; **QSEAL not required or supported**, so **no request-body signing** for LHV. PSD2 ID is Subject OID `2.5.4.97`. See [../../10-security-model.md](../../10-security-model.md).
- **`ACSC` semantics** — source-bank debited and submitted to scheme; final beneficiary settlement is rail-dependent (instant = credited; batch = awaiting clearing). Navesti reports `confirmed`; Sorbet-Core decides settlement meaning.
- **`ACSP` can linger** — usually → `ACSC` in minutes, but may stay on SEPA-Instant→regular fallback, manual intervention, or compliance. Post-SCA, so `side_effect_possible: true`.
- **TLS trust anchor** — LHV server cert chains to DigiCert Global Root G2 (as of 30.03.2026); standard CA bundle suffices for server verification. Client mTLS (our QWAC) is separate.
- **Balances are consent-gated** — unlike `/v1/accounts-list` (no consent), Read Balances is a standard Berlin Group AIS service and requires an AIS consent (`Consent-ID` header). LHV-2A implements the endpoint + normalization and takes a host-supplied `consent_id`; the consent-creation/authorisation flow is deferred. Multiple `balanceType` entries per currency are classified into available/booked and all preserved as raw.

## Sandbox test data (noted, never hardcoded as secrets)

Preset bearer tokens let us exercise AIS/PIS without the OAuth redirect:

- bearer `Liis-MariMnnik` → accounts `EE717700771001735865`, `EE277700771001735881`, `EE457700779900289935`; `PSU-Corporate-ID` `EE47101010033`.
- bearer `Donaldduck` → account `EE857700771001735904`.

Useful fixtures from the docs:
- **Immediate `ACSC`** (SCA-exemption): payment between Liis-Mari's own accounts `EE71…5865` → `EE27…5881` returns `ACSC` with no `scaRedirect`.
- **Redirect required**: a normal cross-owner payment returns `RCVD` + `_links.scaRedirect`.
- Sandbox SCA completes with the PIN-calculator option using any 4 digits (e.g. `0000`).

These tokens/accounts are **sandbox fixtures**, not credentials — fine to reference in tests; do not treat as secrets and do not hardcode them as if they were production auth.
