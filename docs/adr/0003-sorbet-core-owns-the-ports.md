# ADR-0003: Sorbet-Core owns the ports

## Status

Proposed

## Context

Sorbet-Core defines three ports Navesti will back: Connectivity dispatch, AIS BalanceProvider, and Webhook translator. Someone must own the port interfaces and the adaptation between them and Navesti's API — and the dependency direction must be unambiguous.

## Decision

**Navesti implements the concepts that Sorbet-Core ports consume, but Navesti does not import Sorbet-Core.** Port interfaces and the thin wrappers that satisfy them live in the Sorbet-Core repo. Navesti exposes its own value objects and adapter API (docs/02, docs/03); wrappers translate. Navesti's canonical models are fully independent of Sorbet-Core models. Navesti does not know what a Sorbet money packet is.

## Consequences

Good:
- Dependency points one way: kernel → driver. Navesti is testable, releasable, and comprehensible alone.
- Sorbet-Core can evolve packet semantics without Navesti releases.
- The boundary has an executable spec (the conformance suite) instead of shared types.

Bad:
- A translation layer exists in Sorbet-Core that must be maintained (thin by design).
- Vocabulary drift between the two models is possible; the glossary and Phase 3 integration guard it.
- Contract changes require cross-repo coordination.

## Alternatives Considered

1. **Navesti implements Sorbet-Core's port interfaces directly** (imports the kernel) — circular knowledge, kernel concepts leak into the driver, lockstep releases.
2. **Shared contracts gem** — third artifact to version; both sides coupled to it; benefits don't outweigh the ceremony at two-repo scale.
3. **Duck typing with no written contract** — works until the first ambiguous-status incident; unacceptable for money movement.

## Open Questions

- Exact wrapper-visible contract list — open question Q12 in docs/13, to be ratified with the Sorbet-Core side before Phase 3.
