# 00 — Planning Brief

What we are debating before any code is written.

## Mission

Build the bank-driver layer for Sorbet as a headless, stateless Ruby gem in which a bank integration is easy to read, audit, and implement — a *dialect file plus small custom handlers*, not a fork of an adapter superclass.

The guiding question:

> What is the smallest Ruby language in which a bank integration becomes easy to read, audit, and implement?

Not: how do we build a clever framework?

## Non-goals

- Money movement decisions, compliance, ledger, packet state machine — Sorbet-Core owns those.
- Retry/failover orchestration — Navesti reports outcomes once; Sorbet-Core decides retries.
- UI of any kind — banks render SCA, Sorbet-Cockpit renders product UX.
- Persistence — no database, no credential storage, no token storage.
- A generic flow engine or parser engine (OMeta) — explicitly out unless approved later.

## Known Sorbet-Core ports

Navesti will eventually back three ports, defined and owned by Sorbet-Core (see [03-sorbet-core-boundary.md](03-sorbet-core-boundary.md)):

1. **Connectivity dispatch** — submit a normalized payment order, get confirmed / rejected / pending / ambiguous + provider_reference + side_effect_possible + raw evidence.
2. **AIS BalanceProvider** — given a consent/account reference, return balances in minor units with captured_at and raw evidence.
3. **Webhook translator** — given connector + headers + raw body, return a normalized bank event.

Navesti implements the concepts these ports consume but never imports Sorbet-Core. Sorbet-Core writes the thin wrappers.

## Key design tension

**Declarative compression vs. premature abstraction.**

The OMeta/STEPS lesson pulls toward expressing each bank as a tiny declarative dialect (semantic compression, auditability, fast onboarding). The engineering lesson of every dead "universal bank adapter framework" pulls toward writing each adapter as plain Ruby until the repeated shapes are *known*, not guessed.

Our resolution (proposed): plain Ruby value objects and explicit adapters first; the dialect DSL is **extracted in Phase 6** from at least two real adapters plus the mock. When the same bank-specific shape appears three times, we stop and name the language that would express it — not before.

Secondary tensions, debated in [13-open-questions.md](13-open-questions.md):

- One client vs. split AIS/PIS/Webhook clients.
- Ruby DSL vs. YAML vs. plain Ruby tables for dialects.
- Who owns OAuth token refresh.
- How much raw evidence to return (size vs. auditability).

## Questions to answer before implementation

The full list with recommendations lives in [13-open-questions.md](13-open-questions.md). The blocking ones:

1. Are Navesti canonical models independent of Sorbet-Core models? (proposed: yes)
2. One client or split AIS/PIS/Webhook surfaces? (proposed: split, sharing a connection)
3. Dialect representation: Ruby DSL, YAML, or tables? (proposed: Ruby DSL over tables, no YAML)
4. Generic flow engine or adapter-specific flows first? (proposed: adapter-specific)
5. Token refresh ownership? (proposed: Navesti exposes exchange/refresh *calls*; host owns lifecycle/storage)
6. Does Navesti define storage interfaces? (proposed: no — persist nothing, define nothing)
7. What must the mock adapter prove? (proposed: every status category, every interaction type, ambiguity, evidence)

## Success criteria for the planning phase

- We know what Navesti owns.
- We know what Sorbet-Core owns.
- We know what the first mock adapter must prove.
- We know what DSLs are allowed to emerge (and when).
- We know what must not be built yet.
