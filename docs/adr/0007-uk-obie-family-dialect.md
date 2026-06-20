# ADR-0007: A UK OBIE family dialect (Stage 2 of the dialect extraction)

## Status

Accepted

## Context

LHV (Berlin Group), Wise (UK OBIE), and Revolut (UK OBIE) are implemented. Stage 1
(see the `improved-dsl` substrate commit) extracted the mechanics that came out
identical across *all three* dialects — the evidence wrapper, the SSRF origin
guard, the error guard, bearer headers — into plain-Ruby mixins, with no new
vocabulary.

What remains is the **UK OBIE vocabulary** shared by Wise and Revolut: the
consent/payment status tables, the balance-type sets, the permission list, the
per-currency reference limits, and the table-driven normalizers
(`consent_status`, `payment_status`, `available_balance_type?`, `debit?`,
`validate_payment_order!`). The two dialects were byte-for-byte identical here,
differing only in (a) Revolut omitting `ReadDirectDebits` from its registered
permission set and (b) the bank name inside two validation messages.

ADR-0004's three-times rule asks us to name the language once a shape appears a
third time. The *shape* (raw code → normalized fact; "unknown never collapses to
safe") appeared three times (LHV, Wise, Revolut) and was handled in Stage 1. The
OBIE *vocabulary* appears twice. We extract it anyway, as a bounded, deliberate
exception, because it is a **published standard** rather than coincidental
similarity, and a third OBIE bank is on the roadmap.

## Decision

Introduce `Navesti::Dialects::UkObie` — a plain module holding the OBIE tables
(as frozen constants) and the table-driven normalizers (as instance methods). A
provider dialect adopts it with **both** `include` (tables reachable as
`Dialect::CONSTANT`, via the module appearing in the ancestor chain) and
`extend` (normalizers callable as `Dialect.method`), then declares only its
deltas:

```ruby
module Dialect
  include Navesti::Dialects::UkObie
  extend  Navesti::Dialects::UkObie
  PERMISSIONS = (Navesti::Dialects::UkObie::PERMISSIONS - %w[ReadDirectDebits]).freeze # Revolut only
  def self.provider_label = "Revolut"
end
```

This is a table/mixin, **not** a DSL surface and **not** an engine (ADR-0004
holds): the `bank "…" do … end` façade remains a later stage. **Berlin Group
stays a separate dialect** — this groups one standard's vocabulary, never merges
standards. Each future family word is justified the same way: a note citing its
concrete occurrences.

Three concrete occurrences this records:
- `lib/navesti/providers/wise/dialect.rb` — adopts the family, full permissions.
- `lib/navesti/providers/revolut/dialect.rb` — adopts the family, drops `ReadDirectDebits`.
- `lib/navesti/providers/lhv/dialect.rb` — **counter-example**: Berlin Group, intentionally NOT in this family.

## Consequences

Good:
- `wise/dialect.rb` 153 → ~17 lines, `revolut/dialect.rb` 112 → ~21 lines; one
  audited source of the OBIE status/safety semantics.
- A new OBIE bank's dialect is a family adoption plus a handful of deltas — the
  first connector file that reads as mostly a declaration (CLAUDE.md rule 15).
- Behaviour-preserving: the existing per-bank dialect specs are unchanged and
  pass against the shared tables.

Bad / watch:
- `include` + `extend` of the same module is a deliberate two-line idiom (tables
  *and* module functions); it must stay documented so a reader is not surprised.
- The "one family per standard" boundary needs policing — the temptation will be
  to fold Berlin Group in once it too has a second instance. That is a *separate*
  future ADR, not an extension of this one.

## Alternatives Considered

1. **Leave Wise/Revolut duplicated until a third OBIE bank** — strictly honours
   "three times", but re-copies a known standard and invites drift between two
   files that must stay identical.
2. **One mega-dialect for all PSD2 banks** — collapses Berlin Group and OBIE
   together; rejected, it would bury genuine standard differences (e.g. LHV's
   pre-SCA `side_effect_possible: false`) under false unification.
3. **Inheritance (`class WiseDialect < ObieDialect`)** — dialects are modules of
   constants + module functions, not instantiated classes; a mixin fits and
   keeps `Dialect.method`/`Dialect::CONST` access intact.

## Open Questions

- The forthcoming OBIE mapper plumbing (Stage 2b) and Hybrid-Flow adapter
  mechanics (Stage 2c) will extend this family. Do they live under the same
  `Dialects::UkObie` umbrella or sibling `Mappers::UkObie` / `Adapters::UkObieFlow`
  modules? (Current lean: siblings, one concern each.)
