# 07 — Mapping Language

How provider JSON (and later XML) becomes canonical value objects.

## Scope

- **JSON path extraction** — Phase 1+ (every first-wave bank is JSON).
- **XML path extraction** — later (ISO 20022 pain/camt files, some banks' PSD2 APIs). Design must not preclude it; nothing more.
- **Amount conversion** — provider decimal strings ("12.34") → `amount_minor` integers, using the ISO-4217 exponent of the currency. Never `Float` in between: parse as `BigDecimal`/scaled integer. `"12.34" + EUR → 1234`; `"12.3" + JPY → error` (exponent mismatch is a mapping error, not a rounding opportunity).
- **Currency normalization** — uppercase ISO-4217; unknown codes are a mapping error, not passed through.
- **Timestamp parsing** — ISO-8601 with offset → UTC. Bank timestamps without timezone are a per-dialect declaration (`assume_timezone "Europe/Tallinn"`), never a silent default.
- **Presence/absence behavior** — every mapped field is declared `required` or `optional`. Missing required → typed `Navesti::MappingError` naming the field and the path (and carrying raw evidence). Missing optional → `nil`, never a guessed default.
- **Raw evidence preservation** — mapping *adds* a canonical reading; the unmodified payload rides along on the produced object. Mapping never mutates or truncates raw.
- **Error behavior** — a mapping error is not an `ambiguous` payment outcome by itself; it is "the bank answered, we couldn't read it." For PIS responses this surfaces as `unknown`/`ambiguous` per [08-status-normalization.md](08-status-normalization.md) with `side_effect_possible: true`, because the bank *did* receive the request.

## The debate: how to express extraction

| Option | Sketch | Pros | Cons |
|---|---|---|---|
| Manual lambdas | `->(json) { json.dig("balances", "available", "amount") }` | zero machinery, debuggable, infinitely flexible | verbose; absence handling hand-rolled each time; harder to audit at a glance |
| Tiny path helper (ours) | `path("$.balances.available.amount")` → compiled `dig` | reads like bank docs; uniform absence handling; ~50 lines to build | one more thing we own; temptation to grow features |
| `jsonpath` gem | full JSONPath spec | filters, wildcards, recursive descent | dependency weight; spec features we don't want (predicates in mappings = logic hiding in strings) |

## Recommendation

**Manual lambdas first (Phase 1, mock adapter), tiny path helper extracted as soon as the same dig-with-absence-check shape appears three times** — which it will, in the first real AIS adapter. The helper supports exactly: dotted/bracket keys, array index, declared required/optional. No wildcards, no filters, no predicates. Anything fancier is a lambda, visible in the dialect file.

No `jsonpath` gem unless a bank's payloads genuinely need recursive descent (none of the first-wave candidates do).

## Sketch of the eventual mapping table (illustration only)

```ruby
balances do
  field :available, path: "$.balances.available.amount", as: :amount_minor, currency_from: "$.balances.available.currency", required: true
  field :booked,    path: "$.balances.booked.amount",    as: :amount_minor, currency_from: "$.balances.booked.currency",    required: false
  field :captured_at, value: ->(ctx) { ctx.now_utc }
end
```

`as: :amount_minor` is where the decimal-string→minor-units conversion is named once instead of repeated per bank — the kind of vocabulary the three-times rule is meant to surface.
