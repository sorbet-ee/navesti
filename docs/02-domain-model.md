# 02 — Domain Model

Planned value objects only. No implementation. All of these will be **immutable/frozen**, all amounts are **minor units** (`amount_minor` + ISO-4217 `currency`), all timestamps **UTC**, and every provider-derived object **preserves the raw payload** it came from.

Conventions used below: *Raw evidence?* = does the object carry a `raw` field. *Maps to Sorbet-Core?* = the conceptual counterpart (Sorbet-Core performs the mapping in its wrappers; Navesti never sees the counterpart type).

---

## Navesti::Money

- **Purpose:** a quantity of money. The only representation of amounts anywhere in Navesti.
- **Required:** `amount_minor` (Integer, may be negative for AIS transactions), `currency` (ISO-4217 String).
- **Optional:** none.
- **Raw evidence?** No — too primitive; the containing object carries evidence.
- **Maps to Sorbet-Core?** Sorbet-Core's money type (conversion in wrapper).
- **Open questions:** support currencies with non-2 exponent from day one (JPY=0, BHD=3)? Proposed: yes — exponent comes from ISO-4217 table, never hardcoded `* 100`.

## Navesti::Account

- **Purpose:** a bank account as the bank describes it.
- **Required:** `provider_account_id`, `currency`.
- **Optional:** `iban`, `name`, `owner_name`, `account_type`, `status`.
- **Raw evidence?** Yes.
- **Maps to Sorbet-Core?** funding-source / counterparty account references.
- **Open questions:** is a multi-currency account (Wise, Revolut) one Account per currency or one Account with many balances? Proposed: one Account per (provider_account_id, currency) pair — keeps Balance unambiguous.

## Navesti::Balance

- **Purpose:** a balance snapshot at a moment in time.
- **Required:** `account_ref`, `available` (Money), `booked` (Money), `captured_at` (UTC).
- **Optional:** `credit_limit` (Money), `balance_type` (bank's own type label).
- **Raw evidence?** Yes.
- **Maps to Sorbet-Core?** AIS BalanceProvider port output.
- **Open questions:** some banks return only one balance type — is `booked` required or do we allow `available`-only with explicit absence? Proposed: both fields present, value may be `nil` with `raw` showing why; conformance suite has a "missing balance field" case.

## Navesti::Transaction

- **Purpose:** one AIS transaction line (booked or pending entry).
- **Required:** `provider_transaction_id`, `account_ref`, `money` (signed), `booking_status` (:booked/:pending), `booked_at` or `value_dated_at`.
- **Optional:** `counterparty_name`, `counterparty_iban`, `remittance_information`, `end_to_end_id`.
- **Raw evidence?** Yes.
- **Maps to Sorbet-Core?** reconciliation / funding-evidence inputs.
- **Open questions:** do we normalize debit/credit indicators into the sign of `amount_minor`, or keep an explicit `direction` field? Proposed: signed amount **and** explicit `direction`, derived together, so no consumer guesses.

## Navesti::PaymentOrder

- **Purpose:** the normalized instruction Navesti receives from the host. Input object — Navesti never creates or mutates one.
- **Required:** `money`, `debtor` (account ref), `creditor` (name + IBAN/account), `rail` (e.g. :sepa_credit_transfer, :sepa_instant), `end_to_end_reference`, `idempotency_key` (connector-level, supplied by host).
- **Optional:** `remittance_information`, `requested_execution_date`.
- **Raw evidence?** No — it does not originate from a provider.
- **Maps to Sorbet-Core?** Sorbet-Core builds it from its money packet. **Navesti does not know what a packet is.**
- **Open questions:** does the rail belong on the order, or is it implied by which adapter method is called? Proposed: on the order, validated against dialect capabilities.

## Navesti::PaymentSubmission

- **Purpose:** the fact that a payment order was submitted to a bank — the primary output of connectivity dispatch.
- **Required:** `status` (PaymentStatus), `provider_reference` (may be nil only when status is rejected/ambiguous without a reference), `submitted_at`, `idempotency_key` (echoed).
- **Optional:** `interaction` (Interaction, when SCA is required before execution), `bank_status_code` (raw status string).
- **Raw evidence?** Yes — mandatory.
- **Maps to Sorbet-Core?** Connectivity Port output.
- **Open questions:** is "submission accepted but SCA pending" a `pending` status with an interaction, or a distinct state? Proposed: `pending` + interaction present; no extra state.

## Navesti::PaymentStatus

- **Purpose:** the normalized status vocabulary (see [08-status-normalization.md](08-status-normalization.md)).
- **Required:** `category` (:confirmed/:rejected/:pending/:ambiguous/:unknown), `side_effect_possible` (Boolean), `bank_status_code` (original string, may be nil for transport failures).
- **Optional:** `reason_code`, `reason_message` (bank-provided, verbatim).
- **Raw evidence?** Carried by the containing Submission/Event; the status itself stores the original code.
- **Maps to Sorbet-Core?** drives Sorbet-Core's packet state machine — but the mapping from category to packet transition is Sorbet-Core's decision.
- **Open questions:** is `unknown` distinct from `ambiguous`? Proposed: yes — `unknown` = bank answered with a code we don't recognize; `ambiguous` = we don't know whether the bank acted. Both `side_effect_possible: true`.

## Navesti::BankEvent

- **Purpose:** a normalized webhook (or poll-detected) event.
- **Required:** `event_id` (provider's, or fingerprint-derived when absent), `provider_reference`, `event_type`, `occurred_at`, `payload_fingerprint`.
- **Optional:** `status` (PaymentStatus, when the event implies one), `account_ref`.
- **Raw evidence?** Yes — headers + body, mandatory.
- **Maps to Sorbet-Core?** webhook ingestion input; Sorbet-Core decides applied/duplicate/unmatched/rejected/provider_conflict.
- **Open questions:** when a bank sends no event id, is fingerprint-as-id acceptable? Proposed: yes, with `event_id_source: :fingerprint` marked explicitly.

## Navesti::Interaction

- **Purpose:** a render-free descriptor of a step that needs the PSU (see [04-interaction-descriptors.md](04-interaction-descriptors.md)).
- **Required:** `type` (:redirect/:app_redirect/:decoupled/:qr/:poll/:none), `provider_reference`.
- **Optional:** `url`, `expires_at`, `poll_after`, `qr_payload`, `state` (CSRF/anti-forgery token when the flow needs one).
- **Raw evidence?** Yes.
- **Maps to Sorbet-Core?** passed through to Sorbet-Cockpit, which renders UX.
- **Open questions:** does the redirect `state` parameter belong to Navesti or the host? Proposed: host generates state (it owns the callback endpoint); Navesti accepts it as input to URL building.

## Navesti::Consent

- **Purpose:** an AIS consent as granted by the bank.
- **Required:** `provider_consent_id`, `status` (:received/:valid/:rejected/:expired/:revoked), `scope` (accounts/balances/transactions).
- **Optional:** `valid_until`, `frequency_per_day`, `accounts` (when bank restricts to specific accounts).
- **Raw evidence?** Yes.
- **Maps to Sorbet-Core?** stored by host alongside tokens; Navesti never persists it.
- **Open questions:** do consent status values need their own normalization table per bank (a mini status dialect)? Proposed: yes — same mechanism as payment statuses.

## Navesti::Capability

- **Purpose:** machine-readable claims about what a bank dialect supports.
- **Required:** `ais` (Boolean), `pis` (Boolean), `webhooks` (Boolean), `rails` (list), `interactions` (list).
- **Optional:** `instant_rail_fallback` (does the bank auto-fallback instant→regular?), `sandbox` (Boolean).
- **Raw evidence?** No — declared, not derived.
- **Maps to Sorbet-Core?** routing inputs, eventually (see open question 3 in [13-open-questions.md](13-open-questions.md)).
- **Open questions:** how rich must capabilities be for Sorbet-Core routing — flat booleans or structured limits (max amount, cutoff times)? Proposed: flat booleans + rails now; structured limits only when routing needs them.

## Navesti::ProviderReference

- **Purpose:** a typed wrapper for the bank's identifier of a resource, so references are never bare strings confused across banks.
- **Required:** `value`, `kind` (:payment/:consent/:account/:transaction/:event), `connector` (e.g. :lhv).
- **Optional:** none.
- **Raw evidence?** No.
- **Maps to Sorbet-Core?** correlation key for webhooks, polling, reconciliation.
- **Open questions:** is a typed wrapper worth the ceremony vs. plain strings? Proposed: yes — it is the join key of the whole system; typos here are silent data corruption.

---

## Cross-cutting rules

1. Every object frozen at construction; "modification" is `with(...)` returning a new instance.
2. Constructors validate shape (required fields present, currency well-formed, amounts Integer) and raise on violation — bad data fails loudly at the boundary, not three layers in.
3. `raw` is never parsed back out of — it is evidence, not a data source for later steps.
4. No object references Sorbet-Core types, constants, or vocabulary ("packet", "ledger entry") in names or docs.
