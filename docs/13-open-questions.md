# 13 — Open Questions

The planning debate document. Each question has a **default recommendation** — the position Claude proposes we adopt unless debated down — plus alternatives, trade-offs, risk, and whether a decision blocks Phase 1.

Legend: *Decision needed?* **yes** = must be settled before Phase 1 code; **no** = a default is safe to adopt and revisit.

---

## Q1. Should Navesti canonical models be independent of Sorbet-Core models?

- **Default recommendation:** Yes — fully independent. Navesti defines its own frozen value objects; Sorbet-Core wrappers translate.
- **Alternatives:** (a) shared types gem used by both; (b) Navesti imports Sorbet-Core types.
- **Trade-offs:** independence costs a thin translation layer in Sorbet-Core and risks vocabulary drift; sharing couples release cycles and leaks kernel concepts into the driver layer.
- **Risk if wrong:** low — translation layers are cheap to add; un-coupling shared types later is expensive. Independence is the reversible choice.
- **Decision needed?** **Yes** (it shapes every signature). Effectively pre-decided by ADR-0003.

## Q2. One client object or separate AIS/PIS/Webhook clients?

- **Default recommendation:** Separate surfaces — `adapter.ais`, `adapter.pis`, `adapter.webhooks` — sharing one constructed adapter (connection, credentials, dialect). Capability-gated: calling `.pis` on an AIS-only dialect raises at access, not mid-flow.
- **Alternatives:** (a) one flat client with 20 methods; (b) three fully separate classes constructed independently.
- **Trade-offs:** split surfaces mirror the three Sorbet-Core ports 1:1 and keep capability checks at the seam; one flat client is simpler to construct but mixes the read-only world with the money-moving world in one interface.
- **Risk if wrong:** low — facade reshuffling, no contract change.
- **Decision needed?** **Yes** (Phase 1 API shape).

## Q3. Bank dialects: Ruby DSL, YAML, or plain Ruby tables?

- **Default recommendation:** Ruby DSL as surface, evaluating eagerly to frozen plain-Ruby table objects (DSL-over-tables; see [05-bank-dialect-language.md](05-bank-dialect-language.md)). No YAML until non-engineers must edit dialects.
- **Alternatives:** tables only (verbose); YAML (needs schema/validation machinery, can't express quirky logic, splits the dialect across two media).
- **Trade-offs:** DSL costs a small builder and carries DSL-creep risk (mitigated by the three-times rule for vocabulary growth).
- **Risk if wrong:** low — because the substrate is tables, the surface can be swapped without touching adapters.
- **Decision needed?** No for Phase 1 (mock can use bare tables); **yes before Phase 6**.

## Q4. Flow execution: generic engine or adapter-specific at first?

- **Default recommendation:** Adapter-specific. Flows are explicit, ordered adapter methods; the "flow" exists as documentation + conformance tests. No engine ([06-flow-language.md](06-flow-language.md)).
- **Alternatives:** (a) declarative step list executed by a runner; (b) full workflow engine (the `pre_gem` approach — already tried; it absorbed retry/error policy that belongs to Sorbet-Core).
- **Trade-offs:** explicit methods repeat some boilerplate across adapters; an engine compresses it but ossifies the step interface before we know it.
- **Risk if wrong:** asymmetric — extracting an engine from three working adapters is easy; un-building an engine is a rewrite.
- **Decision needed?** **Yes** (it defines what an adapter *is* in Phase 1).

## Q5. Should Navesti own OAuth token refresh or only expose token exchange helpers?

- **Default recommendation:** Helpers only. Navesti exposes `exchange_code`, `client_credentials_token`, `refresh(refresh_token)` as stateless calls returning token objects + evidence. The host stores tokens, tracks expiry, and decides when to refresh.
- **Alternatives:** (a) Navesti-managed token cache with auto-refresh callbacks into host storage; (b) host implements raw OAuth itself.
- **Trade-offs:** helpers keep Navesti stateless and side-effect-free but push scheduling onto every host; auto-refresh is convenient but smuggles in state, locking, and a storage interface (contradicts Q6/ADR-0006).
- **Risk if wrong:** medium — if every host reimplements refresh races, we'll feel it; an optional `TokenManager` utility (host-injected storage) can be added later without breaking the helper layer.
- **Decision needed?** No — helpers-only is safe to adopt; revisit at Phase 4 with real token lifetimes.

## Q6. Should Navesti persist nothing, or define storage interfaces?

- **Default recommendation:** Persist nothing **and define no storage interfaces**. Inputs arrive as arguments; outputs are returned values. The host's persistence never appears in Navesti's type signatures.
- **Alternatives:** define narrow port interfaces (TokenStore, EvidenceStore) the host implements.
- **Trade-offs:** no-interfaces keeps the gem pure and trivially testable; ports would let Navesti orchestrate multi-step flows internally — which we explicitly don't want (Q4).
- **Risk if wrong:** low — adding an optional port later is additive.
- **Decision needed?** **Yes** — pre-decided by ADR-0006; confirm.

## Q7. How much raw bank evidence should be returned?

- **Default recommendation:** Full verbatim body + signature-and-correlation-relevant headers + capture timestamp, on every provider-derived object. Unredacted (evidence ≠ logs; see [10-security-model.md](10-security-model.md)). No size limits in Phase 1.
- **Alternatives:** (a) configurable evidence levels; (b) hashes/fingerprints only; (c) redacted evidence.
- **Trade-offs:** full evidence costs memory/storage (host's problem, host's choice to truncate); anything less makes disputes and reconciliation unprovable. Redacting evidence can destroy bank-signed payloads.
- **Risk if wrong:** low — hosts can drop data they have; nobody can recover data never captured.
- **Decision needed?** No.

## Q8. How do we represent ambiguous vs pending vs unknown?

- **Default recommendation:** Three distinct categories ([08-status-normalization.md](08-status-normalization.md)): `pending` = bank acknowledged and is processing; `ambiguous` = no readable answer, bank may have acted; `unknown` = readable answer, unrecognized code. All three `side_effect_possible: true`. `unknown` never collapses into `rejected`.
- **Alternatives:** (a) fold unknown into ambiguous (loses the "update the dialect" signal); (b) fold ambiguous into pending (catastrophic — pending implies a provider_reference to poll; ambiguous may have none).
- **Trade-offs:** three categories cost Sorbet-Core three handling paths; the alternatives cost correctness.
- **Risk if wrong:** high — this is the double-payment axis. Must align with Sorbet-Core's safety rules before Phase 3.
- **Decision needed?** **Yes** — needs explicit ack from the Sorbet-Core side.

## Q9. How do we handle banks with polling but no webhooks?

- **Default recommendation:** Unify on the BankEvent stream: Navesti exposes `poll_status(provider_reference)`; when a poll observes a change it returns a synthetic BankEvent (`event_id_source: :poll`). **Sorbet-Core schedules polling; Navesti executes exactly one poll per call.** Dialect capability `webhooks false` tells Sorbet-Core polling is required.
- **Alternatives:** (a) Navesti-internal polling loops/threads (violates statelessness and retry rules); (b) two different consumption models in Sorbet-Core (webhook events vs poll results) — duplicate downstream logic.
- **Trade-offs:** synthetic events need careful occurred_at semantics (observed-at vs bank-reported-at — both carried).
- **Risk if wrong:** medium.
- **Decision needed?** No — safe default, revisit at first polling-only bank.

## Q10. How do we guarantee a new bank can be added in 1–2 days?

- **Default recommendation:** Make it a measured target, not a guarantee, enforced by structure: (1) conformance suite is the to-do list; (2) dialect file + small handlers is the deliverable shape (rule 15); (3) an "adapter author's checklist" doc written during Phase 4 from real experience; (4) track actual days-per-adapter from adapter #2 on. The 1–2 day claim becomes credible after Phase 6 extraction, for banks that resemble an existing dialect family.
- **Alternatives:** promise it now (fantasy); abandon the goal (loses the forcing function for semantic compression).
- **Trade-offs / risk:** low — it's a metric, not an API.
- **Decision needed?** No.

## Q11. What is the minimum mock adapter that proves the shape?

- **Default recommendation:** MockNavesti must force, on demand: all five PIS status categories incl. unknown-code; explicit-rejection with `side_effect_possible: false`; timeout→ambiguous; every interaction type (`:redirect`, `:decoupled`, `:poll` minimum); AIS accounts/balances/transactions incl. missing-optional and missing-required fields; signed + malformed + duplicate webhooks; idempotency-key echo; evidence on everything. Anything less and the conformance suite can't exist (Phase 2 depends on it).
- **Alternatives:** happy-path-only mock (then the suite tests nothing that matters).
- **Decision needed?** **Yes** — this is the Phase 1 acceptance criterion.

## Q12. What exact contract must Sorbet-Core wrappers depend on?

- **Default recommendation:** Exactly: (a) the value-object shapes in [02-domain-model.md](02-domain-model.md); (b) the three port input/output contracts in [03-sorbet-core-boundary.md](03-sorbet-core-boundary.md); (c) typed error taxonomy (MappingError, ConsentError, SignatureVerificationFailed, TransportError, …); (d) the conformance suite as the normative spec. Nothing else — no internals, no dialect introspection beyond capabilities.
- **Alternatives:** wrappers reaching into dialects/HTTP internals (boundary erosion).
- **Risk if wrong:** medium — contract gaps surface in Phase 3; that's exactly what Phase 3 is for.
- **Decision needed?** **Yes**, jointly with the Sorbet-Core side, before Phase 3.

## Q13. What should be deferred until real bank pain appears?

- **Default recommendation:** Defer: XML mapping; jsonpath-style path features beyond dig; flow naming layer (Phase 6 gate); TokenManager utility; mTLS/JWS/HMAC implementations (interfaces only until Phase 4–5); structured capability limits (amounts, cutoffs); gem→service split; multi-tenant certificate isolation; YAML dialect surface; retry hints metadata.
- **Alternatives:** build any of these speculatively — each is an OMeta-style temptation: a language feature before three concrete uses exist.
- **Risk:** the real risk is *not* deferring.
- **Decision needed?** No — the list is the default; items exit it via the three-times rule or a named bank requirement.

---

## Summary of blocking decisions (must be answered to start Phase 1)

| Q | Topic | Proposed answer |
|---|---|---|
| Q1 | model independence | independent (ADR-0003) |
| Q2 | client shape | split AIS/PIS/Webhook surfaces |
| Q4 | flow engine | none — explicit adapter methods |
| Q6 | storage interfaces | none (ADR-0006) |
| Q8 | status categories | 5 categories, alignment ack from Sorbet-Core |
| Q11 | mock scope | full status/interaction/evidence matrix |
| Q12 | wrapper contract | value objects + 3 ports + errors + suite |
