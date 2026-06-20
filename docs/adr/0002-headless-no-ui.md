# ADR-0002: Headless, no UI

## Status

Proposed

## Context

Bank integrations involve user-facing moments: consent screens, SCA, payment confirmation. Some bank-integration libraries ship UI for these. We must decide whether Navesti ever renders anything.

## Decision

**No UI in Navesti.** No HTML, CSS, React, bank login pages, consent pages, payment confirmation pages, or operator dashboards. When a flow needs the PSU, Navesti returns an **interaction descriptor** (see docs/04). Sorbet-Cockpit owns product UI; banks own login/SCA/authorization UI.

## Consequences

Good:
- Navesti stays embeddable in any host (web app, worker, CLI, future service).
- No rendering stack, no asset pipeline, no session state — the gem stays stateless and small.
- UI/UX iterations in Cockpit never require a Navesti release.
- Security surface shrinks: no served pages, no CSRF/session handling in the gem.

Bad:
- Every host must implement presentation for each interaction type (redirect, decoupled, QR, poll).
- Interaction descriptors must be expressive enough for UX needs we can't fully foresee (expiry countdowns, app-switch hints).

## Alternatives Considered

1. **Bundled minimal UI** (hosted redirect/consent pages) — convenient for demos, but drags in a web framework, session state, and a whole security model; violates the boundary with Cockpit.
2. **UI helper partials/components shipped with the gem** — couples the gem to a specific frontend stack and version treadmill.

## Open Questions

- Do descriptors need host-facing presentation hints (e.g. recommended message keys), or is `type` + data enough? (Default: type + data; revisit with Cockpit's first integration.)
