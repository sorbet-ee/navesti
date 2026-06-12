# 11 — Conformance Suite

The adapter contract, defined as tests **before** any adapter is implemented. An adapter is a Navesti adapter iff it passes this suite. MockNavesti passes it first (Phase 2); every real adapter (Phase 4+) runs the identical suite plus its own bank-specific tests.

Mechanically (Phase 2): a shared RSpec behavior set (`it_behaves_like "a navesti adapter"`) parameterized by an adapter instance and a scenario harness that can force each outcome (mock: directly; real bank: sandbox fixtures/recordings).

## Suites

### AIS conformance

- lists accounts
- fetches balance
- preserves raw evidence on accounts, balances, transactions
- normalizes `amount_minor` (decimal string → integer minor units, correct exponent per currency)
- handles missing balance field (optional field → nil + evidence, not an exception; missing *required* field → typed MappingError)
- timestamps are UTC (`captured_at` present on balances)
- expired/invalid consent surfaces as typed consent error, not generic failure

### PIS conformance

- confirmed submission → `confirmed`, provider_reference present, evidence present
- explicit rejection → `rejected`, `side_effect_possible: false`, reason preserved verbatim
- pending → `pending`, `side_effect_possible: true`
- pending with SCA → `pending` + Interaction descriptor of a declared type
- ambiguous timeout → `ambiguous`, `side_effect_possible: true`, evidence includes the timeout context
- `side_effect_possible: false` failure → only for explicit rejection / provably-not-sent
- unknown bank status code → `unknown`, never `rejected`, `side_effect_possible: true`
- propagates connector idempotency key (echoed in submission; sent to bank when dialect declares support)
- one call = at most one submission attempt (no hidden retry)

### Webhook conformance

- settled event → BankEvent with status `confirmed`, provider_reference, occurred_at
- failed event → BankEvent with status `rejected`/`unknown` per dialect table
- unknown provider_reference event → still translates (matching is Sorbet-Core's job)
- malformed event → typed parse error carrying raw evidence, not an exception escape or silent nil
- duplicate event id is parseable (translation is pure; dedup is Sorbet-Core's)
- same bytes → same `event_id` + `payload_fingerprint` (determinism)
- signature failure → distinct typed outcome (see security suite)

### Security/error conformance

- redacts secrets from errors (`#inspect`, exception messages, wrapped HTTP errors)
- does not log credentials (assert against a captured logger)
- surfaces signature failure distinctly from parse failure and from verification-not-configured
- credential construction with missing required fields fails at construction

## Suite rules

1. The suite is versioned with the gem; a boundary change without a suite change in the same commit is a contract violation.
2. Suite tests may use only the public adapter API — anything the suite can't reach isn't contract.
3. Real-adapter runs must work against recorded sandbox fixtures (deterministic CI) with an opt-in live-sandbox mode.
