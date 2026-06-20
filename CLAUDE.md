# CLAUDE.md — Navesti Rulebook

> Navesti is the small language of bank connectivity for Sorbet: a headless Ruby gem that describes bank capabilities, flows, mappings, statuses, and webhooks as compact, auditable dialects, then turns them into normalized AIS/PIS facts for Sorbet-Core.

This file is binding for all work in this repository, human or AI.

## Rules

1. **Do not write implementation before Phase 0 planning is accepted.** Phase 0 output is Markdown only.
2. **Navesti is headless.** It is a library, not an application.
3. **Navesti has no UI.** No HTML, CSS, React, login pages, consent pages, confirmation pages, dashboards.
4. **Navesti does not depend on Sorbet-Core.** No gem dependency, no shared constants, no imported types.
5. **Navesti does not own packet state.** It has no payment state machine.
6. **Navesti does not own ledger state.**
7. **Navesti does not decide compliance.**
8. **Navesti does not retry or fail over payments.** It reports outcomes; Sorbet-Core decides what to do next.
9. **Navesti preserves raw provider evidence.** Every normalized fact carries the raw payload it was derived from.
10. **Navesti normalizes facts, not business meaning.** "The bank said ACSC" becomes "status: confirmed, side_effect_possible: true" — never "the packet may settle."
11. **Bank-specific quirks stay inside bank dialect declarations.** Quirks never leak into shared code paths.
12. **Repeated bank integration patterns should become tiny Ruby DSLs or tables.** Mechanics repeated across banks are candidates for a named, declarative description.
13. **Do not implement OMeta or a parser engine** unless explicitly approved.
14. **Prefer readable declarative Ruby over clever meta-programming.** If a reviewer can't audit a dialect in one sitting, it is too clever.
15. **A new bank integration should eventually be mostly a dialect file plus small custom handlers.**
16. **All adapters must pass conformance tests.**
17. **No real bank adapter before mock adapter and conformance suite exist.**
18. **No raw credentials in logs, fixtures, or docs.** Test fixtures use obviously fake values.
19. **All time values are UTC.** ISO-8601 with explicit offset on the wire, UTC internally.
20. **Amounts are `amount_minor`, never `amount_cents`.** Integer minor units plus ISO-4217 currency.

## The Kay/STEPS principle

> When the same bank-specific shape appears three times, stop and name the language that would express it.

We do not implement OMeta. We apply the OMeta/STEPS lesson: repeated integration mechanics become small, explicit, executable descriptions. The goal is semantic compression — a bank integration that reads like the bank's own documentation — not a clever framework.

## Developer browser harness rules

The Makefile and `tools/browser/` harness drive a real browser for human-in-the-loop OAuth/SCA. This is **developer tooling only** — never a runtime dependency of the gem, never imported by `lib/`. Binding rules:

1. Browser automation is opt-in and **sandbox-only by default**.
2. **No headless mode** for bank OAuth/SCA — the human must see the bank UI.
3. **No iframes** — the LHV URL must be visible in the address bar.
4. The LHV URL must be visible (no obscuring/embedding).
5. **Do not automate production credentials.**
6. Do not store bank login credentials.
7. Do not store PIN/SCA codes.
8. Do not record video/trace by default.
9. If screenshots/traces are enabled, write only to `tmp/` and redact URLs containing `code`/`token`.
10. `tmp/lhv/*.json` must be gitignored.
11. `token_set.json` must be `chmod 600`.
12. Never log `access_token`, `refresh_token`, authorization code, cert content, key content, or PEM material.

Selenium is **not** in the gem's dependencies and not in the bundle — the browser scripts require it at runtime and degrade with install instructions if absent. Official installed Firefox is preferred (LHV requires official, unmodified browsers); Playwright Firefox, if ever used, is developer automation only and is not proof of official LHV browser compatibility.

## Phase 0 scope (current)

Allowed: Markdown docs, Mermaid diagrams, ADR files, pseudo-code inside docs, planning questions.

Forbidden: `lib/navesti/*.rb` implementation, HTTP clients, real bank adapters, Faraday/JWT dependencies, Sorbet-Core wiring, OAuth, mTLS, webhook HMAC, Rails/Roda apps, UI, database migrations.
