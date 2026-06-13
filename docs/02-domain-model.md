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

- **Purpose:** a provider account *container* (an IBAN/resource), **not money evidence**. Per-currency monetary values live in Balance, never here.
- **Required:** `provider_account_id`, `provider_reported_currency`.
- **Optional:** `iban`, `name`, `owner_name`, `account_type`, `cash_account_type`, `product`, `status`.
- **Raw evidence?** Yes.
- **Maps to Sorbet-Core?** funding-source / counterparty account references.
- **Decided (multi-currency):** an Account is one container per `provider_account_id`/IBAN; it does **not** split per currency. `provider_reported_currency` is preserved verbatim and may be a multi-currency sentinel — **do not ISO-4217-validate it.** LHV accounts are multi-currency and the accounts-list reports `currency: "XXX"`; some providers send `nil`. Real, ISO-validated currency belongs to `Balance.currency` (one Balance per currency). For LHV the `balances`/`transactions` links are optional on the account object.

  ```
  Account.currency   # provider-reported, may be "XXX" / nil — never validated
  Balance.currency   # actual money currency, ISO-4217 expected
  ```

## Navesti::Balance

- **Purpose:** a balance snapshot for one currency at a moment in time (implemented in LHV-2A).
- **Required:** `provider`, `provider_account_id`, `currency` (real ISO-4217 — **rejects the `"XXX"` container sentinel**), and **at least one** of `available` / `booked`.
- **Optional:** `available` (Money), `booked` (Money) — either may be nil when the bank omits that balance type; `captured_at` (UTC — when Navesti captured it, not the bank's book date); `raw`.
- **Accessors:** `available_amount_minor` / `booked_amount_minor` — flat minor-unit delegators matching the BalanceProvider port contract (docs/03); nil when the underlying Money is absent.
- **Raw evidence?** Yes — preserves *all* raw balance entries for the currency (Berlin Group returns typed entries: `interimAvailable`, `closingBooked`, …) plus the full response.
- **Maps to Sorbet-Core?** AIS BalanceProvider port output. This is the funding-evidence Sorbet-Core's model depends on — accounts identify containers, balances prove money.
- **Decided:** a multi-currency LHV account yields several Balances, one per currency; the dialect classifies each Berlin Group `balanceType` into available/booked (Dialect `AVAILABLE_BALANCE_TYPES` / `BOOKED_BALANCE_TYPES`). A missing available or booked balance is `nil` — Navesti never invents a number. **Read Balances is consent-gated** (unlike accounts-list): the host supplies a `Consent-ID`; the consent-creation flow is a later phase.

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

- **Purpose:** the three-layer normalized status (see [08-status-normalization.md](08-status-normalization.md)).
- **Required:** `status` (rich Navesti label, e.g. `:pending_execution`), `safety_status` (`:confirmed`/`:rejected`/`:pending`/`:ambiguous`/`:unknown`), `side_effect_possible` (`true`/`false`/`:unknown`), `raw_status` (original bank string, may be nil for transport failures).
- **Optional:** `reason_code`, `reason_message` (bank-provided, verbatim), `provider_reference`.
- **Raw evidence?** Yes — carries `raw`; `raw_status` is the verbatim code.
- **Maps to Sorbet-Core?** `safety_status` + `side_effect_possible` are the contract Sorbet-Core acts on; the rich `status` is expressive detail. The mapping from `safety_status` to packet transition is Sorbet-Core's decision.
- **Decided:** rich `status` is first-class Navesti vocabulary; `safety_status` is the minimal Core contract; both always present. `unknown` (unrecognized bank code) and `ambiguous` (we don't know whether the bank acted) stay distinct on the safety axis.

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
