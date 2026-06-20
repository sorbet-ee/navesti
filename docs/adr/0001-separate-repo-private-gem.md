# ADR-0001: Separate repo, private gem

## Status

Proposed

## Context

Navesti is the bank connectivity layer for Sorbet. Sorbet-Core is a protocol kernel that owns money packets, state, compliance, routing, ledger, idempotency, audit, and tenancy. We need to decide where bank-driver code lives and how it is packaged, before either codebase grows assumptions about the other.

## Decision

Navesti lives in its own repository, `sorbet-ee/navesti`, and is packaged as a **private Ruby gem** (`gem "navesti"`, namespace `Navesti`). Library/gem first; a standalone service only if later forced by security, scaling, or certificate isolation — via a new ADR.

## Consequences

Good:
- Hard dependency boundary: Navesti physically cannot import Sorbet-Core.
- Independent release cadence; Sorbet-Core pins a version range.
- Bank-credential-adjacent code is reviewable in isolation (audit surface).
- Reusable by other hosts (jobs, future services) without dragging the kernel along.

Bad:
- Cross-repo changes (boundary evolution) need coordinated releases.
- Private gem hosting/credentials in CI must be maintained.
- Two repos to keep conventions aligned across.

## Alternatives Considered

1. **Inside Sorbet-Core** — fastest day one; boundary erodes by convenience, kernel imports leak in.
2. **Microservice** — strongest isolation, but adds a network hop, deployment, and authn between us and ourselves before any real need exists.
3. **Monorepo package** — middle ground; tooling discipline replaces physical separation, and our tooling for that doesn't exist yet.

## Open Questions

- Gem hosting: private gem server vs git-sourced Gemfile entry (decide in Phase 1).
- What measurable trigger (cert isolation? tenant scaling?) would revisit the service question (Phase 7).
