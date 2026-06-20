# 15 — Connector roadmap & status (working notes)

> Living status note for later reference — where each bank connector stands and
> what's next. Not a design doc; update as things move.

## Status

- **LHV (Berlin Group)** — done, merged. AIS + PIS + webapp.
- **Wise (UK OBIE 3.1.11)** — AIS + PIS merged (PRs #7, #8). Webapp on branch
  `wise-webapp` (committed, **PR pending**). **BLOCKED on sandbox certs**: Wise
  OBIE has no presets — emailed `openbanking@wise.com` for the OBWAC (transport)
  + OBSeal (signing) certs and a registered `client_id`. Nothing runs live until
  those land. The code is cert-independent and green (235 examples); the moment
  certs arrive, `WISE_LIVE=1 make wise-webapp` should walk the whole flow.
  - **Wise Public API** (the Platform/token product, NOT OBIE) is an
    *alternative* testable now with a sandbox API token (no mTLS): profiles,
    multi-currency balances, quotes/FX, transfers, sandbox lifecycle
    **simulation**, webhooks. SCA is a signed-token (`X-Signature`), not a
    redirect. A genuinely different connector. **Parked, not chosen.**

## Next: Revolut Business connector

Chosen as the next connector because the cert is **self-serve** (no waiting):
you generate your own keypair and upload the public cert + JWKS in the Revolut
sandbox portal — the opposite of Wise OBIE's email-and-wait.

- **Auth:** OAuth2 + `private_key_jwt` client assertion (Revolut uses **RS256**).
  Reuses `security/jws` — add a `sign_rs256` next to the existing PS256.
- **Scope:** AIS + PIS (Business API).
- **Already planned:** `docs/12` adapter #5 — *"OAuth2 with signed JWT client
  assertion; consent redirect for OB. AIS: yes. PIS: yes (Business API)."*
- **Prior art in-repo — reference only, do NOT port (docs/12 §"Order"):**
  - spikes: branches `navesti_revolut` (`revolut_ais_flow.rb`,
    `revolut_pis_flow.rb`), `revolut_ob_client` (`lib/revolut_ob_client.rb`)
  - cert groundwork: `config/certs/revolut.csr`, and a `jwks.json` in master
    from that exploration
- **Significance:** the **third dialect** → the ADR-0004 "three-times" threshold
  where the shared operation/mapper/status-table extraction (docs/14) starts to
  pay off. Build Revolut straight first (naive, per STEPS), then reassess
  extraction with three concrete occurrences in hand.

## Open items before writing the Revolut adapter

1. Inspect the existing `revolut.csr` / `jwks.json` / spike branches — how much
   of the cert/JWKS/auth setup is reusable as reference.
2. Verify the **current** Revolut Business *sandbox* docs (self-generated cert,
   `private_key_jwt` token exchange, endpoints, scopes, SCA/`X-Signature`).
3. Scope the `providers/revolut/` quartet from scratch against the conformance
   suite — config / dialect / mappers / adapter, mirroring LHV + Wise.

## Watch-list carry-over (docs/14)

Revolut is the occurrence that should justify extracting the shared mechanics.
Going in, expect the same duplication confirmed for Wise — operation envelope,
`evidence` redaction, balance/status tables, origin-pinned `absolute()` — and
expect the auth (OAuth + `private_key_jwt`) to stay a pluggable handler that the
JWS helper already covers.
