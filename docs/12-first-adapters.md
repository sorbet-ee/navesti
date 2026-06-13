# 12 — First Adapters

Planned order. **No adapter is coded in Phase 0.**

## Prior art in this repo (input to this plan)

Earlier branches contain working spike flows — pre-gem, no normalization/mapping layer, but real bank conversations:

| Branch | Bank | State |
|---|---|---|
| `navesti_lhv`, `lhv_navesti`, `codex/rewrite-lhvapiclient-...` | LHV | AIS + PIS flows run; auth works; sandbox mTLS certs exist |
| `navesti_seb` | SEB | AIS + PIS "like ob clients", no mapping |
| `navesti_swedbank` | Swedbank | AIS + PIS via early DSL |
| `navesti_boc` | Bank of Cyprus | AIS + PIS, no mapping |
| `navesti_nbog` | National Bank of Greece | AIS + PIS, no mapping |
| `navesti_paypal` | PayPal | AIS-ish + order flow |
| `navesti_revolut`, `revolut_ob_client` | Revolut | AIS flows |

These spikes de-risk auth flows and endpoint quirks; they are *reference material*, not code to port. The new adapters are written against the conformance suite from scratch.

## Order

### 1. MockNavesti (Phase 1–2)

- **Why:** the executable definition of the adapter contract. Proves every shape — all five status categories, every interaction type, ambiguity, evidence, idempotency echo — before any network call exists.
- **Auth flow:** simulated (configurable: redirect or decoupled).
- **AIS:** yes — accounts, balances, transactions, missing-field cases.
- **PIS:** yes — every status row from [08-status-normalization.md](08-status-normalization.md), forceable per call.
- **Webhook/polling:** both — synthetic signed webhooks and poll-emitted events.
- **Known quirks:** none; it exists to *generate* the awkward cases deliberately.
- **Documents needed:** none. **Credentials:** fake by construction.

### 2. LHV — Phase 1 vertical slice (active)

Estonian **LHV Pank PSD2 / Berlin Group** interface (`api.lhv.eu/psd2` — *not* the UK LHV Bank Limited / Salt Edge product). One end-to-end journey, smallest slice that proves the architecture. Berlin Group REST/JSON, mTLS/QWAC only (no QSEAL). Details in [providers/lhv/swagger-notes.md](providers/lhv/swagger-notes.md); status dialect in [08-status-normalization.md](08-status-normalization.md).

**Included (Phase 1):**

- TPP verification (`GET /v1/tpp-verification`)
- OAuth redirect URL builder
- OAuth token exchange (`POST /oauth/token`, authorization_code)
- AIS accounts-list, **no-consent** variant (`GET /v1/accounts-list`)
- PIS SEPA **JSON** initiation (`POST /v1.1/payments/sepa-credit-transfers`)
- PIS status polling (`GET /v1.1/.../{paymentId}/status`)
- LHV status dialect (rich label + safety_status + side_effect_possible)

**Excluded (later phases):**

- XML payments / bulk / international / UK FPS / SWIFT
- decoupled SCA execution
- PIIS (confirmation of funds)
- payment cancellation
- balances & transactions endpoints
- consent lifecycle (long/short-term consents)
- token refresh / revoke
- real persistence, Sorbet-Core wrapper, UI

- **Auth flow:** OAuth2 redirect + mTLS (sandbox test certs). For AIS/PIS smoke tests, sandbox ships preset bearer tokens (`Liis-MariMnnik`, `Donaldduck`) so the redirect dance isn't required to exercise the data calls.
- **Webhook/polling:** polling only.
- **Known quirks:** multi-currency accounts report `currency: "XXX"`; RCVD/RVCD spelling variance; ACSP can linger.
- **Credentials/certificates:** sandbox client cert/key in gitignored `certs/`, referenced by env path (`LHV_CLIENT_CERT_PATH` etc.); TPP id `PSDEE-LHVTEST-e37b7b` (extractable from cert OID 2.5.4.97). The old pair committed in `navesti_lhv` branch history must not be reused. Regenerate the sandbox pair when convenient — it doesn't block implementation.

### 3. LHV — later phases (PIS hardening, AIS depth)

- **Why:** extend the proven dialect — balances/transactions, consent lifecycle, decoupled SCA, cancellation, token refresh, then XML.
- **Expected auth flow:** as Phase 1, plus payment SCA depth.
- **AIS:** already done. **PIS:** SEPA credit transfer (+ instant if sandbox supports).
- **Webhook/polling:** per sandbox support; polling fallback regardless.
- **Documents needed:** payment initiation API docs, status code list (ISO 20022 subset).

### 4. Wise (AIS/PIS)

- **Why:** non-PSD2-shaped API (proprietary REST, token auth, no SCA redirect dance) — the best stress test that our abstractions aren't secretly "PSD2 only". Multi-currency accounts stress the Account/Balance model. Webhooks exist and are HMAC-signed — first real webhook conformance run.
- **Expected auth flow:** API token (business), OAuth for some surfaces; no PSU redirect in the common path.
- **AIS:** balances/statements. **PIS:** transfers.
- **Webhook/polling:** webhooks (signed) + polling.
- **Known quirks:** sandbox is easy to access — argument for promoting Wise earlier (see debate below).
- **Credentials:** sandbox API token.

### 5. Revolut Business / Open Banking

- **Why:** popular counterparty; prior AIS spike exists; OAuth + JWT client assertions exercise the signing helpers.
- **Expected auth flow:** OAuth2 with signed JWT client assertion; consent redirect for OB.
- **AIS:** yes. **PIS:** yes (Business API).
- **Webhook/polling:** webhooks available.
- **Known quirks:** cert/JWKS registration (the `jwks.json` in this repo's master is from that exploration).

## Debate: LHV-first vs Wise-first

| | LHV first | Wise first |
|---|---|---|
| Sandbox friction | mTLS certs, onboarding | trivial (token) |
| Representativeness | PSD2/Baltic banks (most of the roadmap) | proprietary APIs |
| Prior de-risking | spike branches exist | spike exists (pre_gem example) |
| Business value | home bank, real settlement path | broad counterparty coverage |

**Recommendation:** keep **LHV first** — it's the business-critical rail, the spike removed the auth unknowns, and a PSD2-shaped first adapter exercises more of the planned machinery (mTLS, consents, SCA interactions). **But** if sandbox re-onboarding stalls more than ~a week, swap Wise in as #2 — the conformance suite makes the order safe to change. Decision owner: Angelos (sandbox access reality decides).
