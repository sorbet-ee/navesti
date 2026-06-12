# ROADMAP

## Phase 0 — Planning debate *(current)*

Docs-only. Architecture, domain model, boundary contracts, dialect-language sketches, ADRs, open questions. Exit criterion: Angelos, GPT, and Claude have debated and accepted the answers to [docs/13-open-questions.md](docs/13-open-questions.md).

## Phase 1 — Gem skeleton + value objects + mock adapter

Empty gem scaffold, frozen value objects ([docs/02-domain-model.md](docs/02-domain-model.md)), and `MockNavesti` — an in-memory adapter exercising every status category, ambiguous outcomes, interactions, and webhook shapes. No HTTP, no real bank.

## Phase 2 — Conformance suite

Shared RSpec contract tests ([docs/11-conformance-suite.md](docs/11-conformance-suite.md)) that any adapter must pass. MockNavesti is the first adapter to pass them; the suite is the executable definition of "adapter."

## Phase 3 — Sorbet-Core wrapper integration

Sorbet-Core (in its own repo) writes thin wrappers implementing its Connectivity, AIS BalanceProvider, and Webhook-translator ports on top of Navesti, against MockNavesti. Proves the boundary contract from both sides without any real bank.

## Phase 4 — First AIS real connector

First real bank, **read-only**: consent, token exchange, accounts, balances, transactions, evidence preservation. Candidate: LHV sandbox (see [docs/12-first-adapters.md](docs/12-first-adapters.md)).

## Phase 5 — First PIS real connector

Payment initiation against the same bank's sandbox: payment intent, SCA interaction, submission, status polling/webhooks, ambiguity handling.

## Phase 6 — Bank dialect DSL extraction

With 2–3 adapters written, extract the repeated shapes into the dialect DSL ([docs/05-bank-dialect-language.md](docs/05-bank-dialect-language.md)). The DSL is *extracted from* working adapters, never designed ahead of them.

## Phase 7 — Production hardening

mTLS, JWS request signing, token lifecycle helpers, redaction audit, fixture audit, certificate isolation review (and the gem-vs-service question revisited only if security or scaling forces it).

## Why AIS before real PIS

AIS validates consent, token, account, balance, and evidence flows **without initiating money movement**. Every mechanic PIS needs — OAuth, SCA interactions, mapping, evidence, conformance — gets proven on a path where the worst failure is a stale balance, not a duplicated payment.
