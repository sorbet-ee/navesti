# 08 — Status Normalization

The most safety-critical mapping in Navesti. A wrong reading here can cause Sorbet-Core to double-send or falsely cancel money movement. **This document aligns with Sorbet-Core's safety rules.**

## The chain of meaning

A bank status code is translated through three layers — the OMeta/STEPS lesson applied: each layer is a small, declared transformation, and every layer preserves the layer below.

```
raw_status            (verbatim bank code, e.g. "ACSP")
  -> status           (rich Navesti semantic label, e.g. :pending_execution)
  -> safety_status    (coarse safety class Sorbet-Core acts on, e.g. :pending)
     + side_effect_possible   (true | false | unknown)
  -> Sorbet-Core decision surface
```

- **`raw_status`** — the exact bank string, never discarded.
- **`status`** — Navesti's *expressive* vocabulary. Banks get rich dialects; this is where LHV's distinctions survive even when Sorbet-Core would collapse them.
- **`safety_status`** — the *minimal* contract Sorbet-Core depends on. Boring on purpose.
- **`side_effect_possible`** — could money have moved, or still move, because of this attempt?

Navesti gets expressive bank dialects. Sorbet-Core gets a minimal safety contract. The `status → safety_status` reduction is a shared default table; `side_effect_possible` is set per (bank, code) because it is safety-critical and bank-specific.

```ruby
Navesti::PaymentStatus.new(
  status:               :pending_execution,
  safety_status:        :pending,
  raw_status:           "ACSP",
  side_effect_possible: true,
  provider_reference:   "ac8bab09-fdda-4b6d-8776-3a0583df574a",
  raw:                  { ... }
)
```

## The vocabularies

### Rich Navesti status (expressive)

`requires_authorization`, `partially_authorized`, `pending_execution`, `pending_execution_with_warning`, `confirmed`, `rejected`, `cancelled`, `pending_xml_signature`, `unknown`.

This list grows per the three-times rule as more banks are added. A bank may emit a label Sorbet-Core treats identically to another — that is fine; Navesti normalizes the *fact*, Sorbet-Core decides the *action* (rule 10).

### Safety status (minimal contract)

`confirmed`, `rejected`, `pending`, `ambiguous`, `unknown`.

### side_effect_possible

`true`, `false`, `unknown`. It is `false` only when provably so: an explicit bank rejection, or a failure before the request left. **When in doubt, never `false`.**

## LHV status dialect

The Berlin Group / LHV codes, mapped through the chain. (`raw_status` → `status` | `safety_status` | `side_effect_possible`.)

| raw_status | status | safety_status | side_effect_possible | notes |
|---|---|---|---|---|
| `RCVD` | `requires_authorization` | `pending` | **false** | pre-SCA; validated, awaiting authorization |
| `RVCD` | `requires_authorization` | `pending` | **false** | doc spelling variant of RCVD — same meaning |
| `PATC` | `partially_authorized` | `pending` | **false** | multi-signature partial (XML only); not fully authorized |
| `ACSP` | `pending_execution` | `pending` | **true** | post-SCA, awaiting execution — may move money any moment |
| `ACWC` | `pending_execution_with_warning` | `pending` | **true** | post-SCA, minor automatic changes; processing continues |
| `ACSC` | `confirmed` | `confirmed` | **true** | debited from payer and submitted to scheme |
| `RJCT` | `rejected` | `rejected` | **false** | final, explicit rejection |
| `CANC` | `cancelled` | `rejected` | **false** | final; periodic-payment context only |
| `PDNG` | `pending_xml_signature` | `pending` | **unknown** | XML payment awaiting signature |
| *(any other / absent)* | `unknown` | `unknown` | **true** | unrecognized code — never `rejected` by default |

### The double-spend boundary: RCVD/RVCD vs ACSP

This is the single most important line in the LHV dialect.

- **`RCVD` / `RVCD` — pre-SCA.** The payment is validated and a `scaRedirect` is offered, but nothing executes without the PSU completing SCA. Abandoning here is safe from a money-movement standpoint → `side_effect_possible: false`. (The sample JSON initiation response shows `transactionStatus: "RCVD"` *with* an `scaRedirect` link.)
- **`ACSP` — post-SCA.** SCA is complete; the bank is executing. It is usually followed by `ACSC` in minutes, but can sit in `ACSP` for longer when it falls back from SEPA Instant to regular SEPA, or needs manual/compliance intervention. **It cannot be retried blindly** → `side_effect_possible: true`.

### Rules

1. **Unknown statuses are never safe by default** — `safety_status: :unknown`, `side_effect_possible: :true_or_unknown`, never `:rejected`.
2. **`ACSC` means source-bank confirmed** — debited and submitted to the scheme. For SEPA Instant that also means credited to the receiver; for batch SEPA/SWIFT it means awaiting clearing. So Navesti calls it `confirmed` (source-bank fact), **not** "beneficiary settled." Sorbet-Core decides whether that counts as settlement for a given rail.
3. **`side_effect_possible` is not uniform across `pending`** — it is `false` pre-SCA (RCVD/RVCD/PATC) and `true` post-SCA (ACSP/ACWC). The safety axis carries the distinction the coarse `pending` class hides.

## Transport-level outcomes (no bank code)

These arise from the connection, not a bank status. They never come with a `raw_status`.

| Situation | status | safety_status | side_effect_possible |
|---|---|---|---|
| timeout | `unknown` | `ambiguous` | `true` |
| transport failure after request may have left | `unknown` | `ambiguous` | `true` |
| connection failed before request written | `rejected` *(or typed local error)* | `rejected` | `false` |
| mapping error on a 2xx response | `unknown` | `ambiguous` | `true` |

## Where mappings live

- Bank code → rich `status` + `side_effect_possible`: **Navesti LHV dialect** (requires reading bank docs).
- Rich `status` → `safety_status`: **shared Navesti default table**.
- `safety_status`/`side_effect_possible` → packet state transition: **Sorbet-Core**. Navesti never says "settle the packet."

## Conformance hooks

The suite ([11-conformance-suite.md](11-conformance-suite.md)) pins every LHV row, plus: unknown code ≠ rejected; RCVD `side_effect_possible: false`; ACSP `side_effect_possible: true`; timeout → ambiguous; explicit rejection → `side_effect_possible: false`.
