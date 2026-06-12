# ADR-0006: No persistence inside Navesti

## Status

Proposed

## Context

Bank connectivity touches things that *want* to be stored: OAuth tokens, consents, raw evidence, webhook events, idempotency records. If Navesti stores any of them it acquires a database dependency, migrations, multi-tenancy concerns, and state that breaks its pure call-in/fact-out model — all of which Sorbet-Core (or the host) already owns.

## Decision

**Navesti is stateless and persists nothing.** No database dependency, no file storage, no caches that outlive a call. The host application supplies credentials and tokens as call/constructor arguments and persists evidence, consents, and events from Navesti's returned value objects. Navesti defines no storage interfaces either (docs/13 Q6) — its signatures never mention a store.

## Consequences

Good:
- Every adapter call is a pure function of (inputs, credentials, bank response) — trivially conformance-testable.
- No migrations, no tenancy model, no data-retention obligations inside the gem.
- The gem can run anywhere the host runs, including inside jobs and tests, with zero infrastructure.
- Evidence persistence lives in one trust domain (the host's), simplifying audit.

Bad:
- Hosts carry more: token storage and refresh scheduling, evidence persistence, consent records.
- Multi-step flows require the host to shuttle references between calls (mitigated: that's also what keeps flows explicit).
- A future optional convenience (e.g. TokenManager with host-injected storage) may be demanded; adding it must not erode the no-interface default.

## Alternatives Considered

1. **Navesti-owned storage (own tables/Redis)** — convenient autonomy; imports tenancy, retention, and migration problems into a driver gem, and duplicates Sorbet-Core's evidence store.
2. **Storage *interfaces* defined by Navesti, implemented by host** — looks clean, but invites Navesti to orchestrate stateful flows internally, which we explicitly rejected (no flow engine, no retries).

## Open Questions

- Is an in-call memoization (e.g. token reused across two requests within one adapter call) "state"? (Default: allowed — lifetime ≤ one call.)
