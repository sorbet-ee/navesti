# 05 — Bank Dialect Language

**The heart of the planning debate.** Not implemented yet — sketched here so the debate happens on paper, not in code review.

## Purpose

> A bank dialect describes what the bank means.

One bank = one dialect: a compact, auditable declaration that a reviewer can check against the bank's API documentation side-by-side. Everything bank-specific — quirks included — lives here, never in shared code paths.

A dialect may include:

- capabilities (AIS/PIS/webhooks, rails, interaction types)
- auth profile (OAuth variant, mTLS, signing requirements)
- status mappings (PIS statuses, consent statuses)
- error mappings
- webhook event mappings (+ signature scheme)
- balance mappings
- transaction mappings
- interaction types per flow
- required headers
- idempotency behavior (does the bank honor a key? which header?)
- side_effect semantics per status/error

## Example sketch (not final, not implemented)

```ruby
bank "mock_navesti" do
  capabilities do
    ais true
    pis true
    webhooks true
    rails :sepa_credit_transfer, :sepa_instant
    interactions :redirect, :decoupled
  end

  pis_statuses do
    map "ACSC", to: :confirmed, side_effect_possible: true
    map "RJCT", to: :rejected,  side_effect_possible: false
    map "PDNG", to: :pending,   side_effect_possible: true
  end

  balances do
    available path("$.balances.available.amount")
    booked    path("$.balances.booked.amount")
    currency  path("$.balances.available.currency")
  end
end
```

## The three candidate surfaces

### Option A — Plain Ruby objects

```ruby
MockBank = BankDialect.new(
  key: "mock_navesti",
  statuses: {
    "ACSC" => Status.confirmed,
    "RJCT" => Status.rejected(side_effect_possible: false)
  }
)
```

### Option B — Ruby DSL

```ruby
bank "mock_navesti" do
  status "ACSC", to: :confirmed
  status "RJCT", to: :rejected, side_effect_possible: false
end
```

### Option C — YAML-ish external file

```yaml
bank: mock_navesti
statuses:
  ACSC:
    to: confirmed
  RJCT:
    to: rejected
    side_effect_possible: false
```

## Comparison

| Criterion | A: Plain Ruby objects | B: Ruby DSL | C: YAML |
|---|---|---|---|
| Readability next to bank docs | medium (constructor noise) | **high** | high |
| Auditability (diff review) | high | high | high |
| Testability | **high** (just objects) | high (DSL evaluates to A's objects) | medium (load step between file and behavior) |
| Custom escape hatches (lambdas, conditionals) | native | **native, controlled** | none — forces a second mechanism |
| Validation timing | construction | construction | parse + schema validation we must build |
| Tooling cost | zero | small (a builder) | parser, schema, error reporting |
| Editable by non-engineers | no | no | yes (theoretical) |
| Risk | verbosity discourages declaring | DSL creep into a framework | "stringly-typed" logic; quirks won't fit and leak into Ruby anyway |

## Recommendation

**B over A, with B defined as nothing but a thin builder over A.** The DSL must evaluate eagerly to frozen plain-Ruby table objects (Option A is the substrate, Option B is the surface). That gives:

- Readability of B, testability of A — tests can construct `BankDialect` objects directly.
- Escape hatches stay Ruby: a quirky status mapping is a lambda in place, visible in the same file, not a plugin system.
- No YAML (Option C) until a real non-engineer needs to edit dialects — which is not a Phase 1–6 scenario. YAML's apparent simplicity dies on the first bank whose status depends on two fields.

This matches the stated bias: *Ruby DSL first, plain Ruby tables underneath, no YAML until non-engineers need it.*

## Prior art in this repo

Earlier branches (`pre_gem`, `navesti_lhv`, `navesti_seb`, `navesti_swedbank`, `navesti_boc`, `navesti_nbog`, `navesti_paypal`, `navesti_revolut`) contain a ~660-line workflow DSL (`map` / `step` / `check` / `branch` / `on_error` / `format`) and per-bank flow scripts (the LHV AIS flow is ~37 lines on top of it). Lessons to carry forward:

- The per-bank surface *can* be very small — that's validated.
- The old DSL mixed **mapping**, **flow control**, and **error handling** into one engine; the new design separates dialect (facts about the bank) from flow (sequence of calls) from mapping (extraction), per docs [06](06-flow-language.md) and [07](07-mapping-language.md).
- Retry logic lived inside workflow branches (`sleep 5; retry`) — exactly what rule 8 now forbids. Dialects declare facts; Sorbet-Core decides retries.

## Debate questions

1. **Internal Ruby DSL, YAML, or pure Ruby tables?** Proposed: DSL-over-tables (above). Decision needed before Phase 6, not before Phase 1.
2. **How much declarative vs. custom Ruby?** Proposed rule: declarative for the regular 80% (statuses, paths, headers, capabilities); a named lambda/method in the same dialect file for the rest. A dialect with >30% custom code means the DSL vocabulary is missing a concept — name it (the three-times rule).
3. **Should capabilities be machine-readable enough for routing later?** Proposed: yes — capabilities are plain frozen data precisely so Sorbet-Core routing can consume them through the wrapper without Navesti knowing routing exists.
4. **Should status mapping live in Navesti or Sorbet-Core?** Proposed: bank-code → category mapping (ACSC→confirmed) lives in Navesti dialects, because it requires reading the bank's docs. Category → packet-state-machine meaning lives in Sorbet-Core. Two tables, two owners, one boundary.

## What we will not do

- No registry that auto-discovers dialects via `inherited` hooks or const scanning.
- No DSL feature added speculatively — vocabulary enters only via the three-times rule.
- No OMeta, no grammar engine, no string-parsed mini-language (ADR-0004).
