# ADR-0005: No real bank before mock conformance

## Status

Proposed

## Context

Real bank work is seductive: sandbox access exists, prior spike branches (LHV, SEB, Swedbank, BOC, NBOG, PayPal, Revolut) already talk to banks, and demos demand it. But interfaces designed against one real bank inherit that bank's shape, and failure cases (timeouts, ambiguous outcomes, unknown statuses) are nearly impossible to produce on demand against a sandbox.

## Decision

**Build the mock adapter (MockNavesti) and the conformance suite before any real bank adapter** (LHV/Wise/Revolut). The mock must force every status category, interaction type, ambiguity case, and webhook shape (docs/13 Q11). The suite is the executable adapter contract; real adapters are written *to* it.

## Consequences

Good:
- The adapter contract is shaped by the full outcome matrix, not by whichever bank came first.
- Ambiguity/safety behavior (side_effect_possible, unknown ≠ rejected) is pinned by tests before money is reachable.
- Sorbet-Core wrapper integration (Phase 3) can proceed with zero bank credentials.
- Every later adapter has an objective done-definition.

Bad:
- Delays first real-bank demo by Phases 1–2.
- Risk of mock fantasy: the mock may encode wrong guesses about real bank behavior — mitigated by the prior spike branches as reference material and by revising mock + suite when LHV teaches us otherwise.

## Alternatives Considered

1. **LHV first, extract contract afterwards** — fastest demo; contract becomes "whatever LHV does", and ambiguity paths stay untested until a production incident tests them for us.
2. **Mock and first real adapter in parallel** — feedback both ways, but splits focus and tempts contract changes mid-flight; acceptable fallback if Phase 2 stalls.

## Open Questions

- How much real-bank behavior (from spike branches) should seed the mock's fixtures? (Default: status codes and payload shapes, yes; timing quirks, no.)
