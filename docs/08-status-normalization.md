# 08 — Status Normalization

The most safety-critical mapping in Navesti. A wrong status category here can cause Sorbet-Core to double-send or falsely cancel money movement. **This document must align with Sorbet-Core's safety rules.**

## PIS status categories

| Category | Meaning | side_effect_possible |
|---|---|---|
| `confirmed` | bank says the payment is executed/settled/completed | `true` (money moved) |
| `rejected` | bank affirmatively refused | `false` — only with explicit rejection |
| `pending` | bank accepted and is processing (or awaiting SCA) | `true` |
| `ambiguous` | we cannot know whether the bank acted | `true`, always |
| `unknown` | bank answered with a status code not in the dialect | `true` |

`ambiguous` vs `unknown`: ambiguous = *no readable answer* (timeout, transport failure, unparseable response after the request may have left). Unknown = *a readable answer we don't recognize* (new status code the dialect hasn't mapped). Both are escalation signals to Sorbet-Core; they differ in remediation (retry/reconcile vs. update the dialect).

## side_effect_possible

One question: **could money have moved, or still move, because of this attempt?**

It is `false` only when one of these holds provably:

1. The bank explicitly rejected the request (`RJCT` and kin).
2. The failure occurred before the request left (local validation failure, DNS/connect failure before any bytes were written).

Everything else — including "probably failed" — is `true`. Sorbet-Core's retry and reconciliation logic depends on this bit being conservative.

## Rules

| Situation | Category | side_effect_possible |
|---|---|---|
| timeout | `ambiguous` | `true` |
| transport failure after request may have left | `ambiguous` | `true` |
| explicit bank rejection | `rejected` | `false` |
| provider says accepted/pending | `pending` | `true` |
| provider says completed/settled | `confirmed` | `true` |
| unknown provider status code | `unknown` (never `rejected`) | `true` |
| connection failed before request written | `rejected` (or typed local error) | `false` |
| HTTP 4xx validation error on submission | `rejected` | `false` — only if the bank semantics guarantee no processing; per-dialect decision, default `true` |
| HTTP 5xx on submission | `ambiguous` | `true` |
| mapping error on a 2xx response | `unknown` | `true` |

The 4xx row is deliberately uncomfortable: some banks return 400 *after* creating a resource. The dialect declares, per error code, whether the bank guarantees no side effect. **Default when undeclared: `true`.**

## Where mappings live

- Bank status code → category + side_effect bit: **Navesti dialect** (requires reading bank docs; e.g. ISO 20022 `ACSC`/`ACCC`/`ACSP`/`RJCT`/`PDNG`/`RCVD` per bank, since banks disagree on nuances).
- Category → packet state transition: **Sorbet-Core**. Navesti never says "settle the packet."

## Consent/AIS statuses

Same mechanism, lower stakes, separate table (`consent_statuses`): received/valid/rejected/expired/revoked. No side_effect bit (no money moves), but `unknown` still must not collapse into `rejected`.

## Conformance hooks

The suite ([11-conformance-suite.md](11-conformance-suite.md)) pins every row of the rules table against the mock adapter, including: unknown code ≠ rejected, timeout → ambiguous + side_effect_possible, explicit rejection → side_effect_possible false.
