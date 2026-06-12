# Navesti

> Navesti is the small language of bank connectivity for Sorbet: a headless Ruby gem that describes bank capabilities, flows, mappings, statuses, and webhooks as compact, auditable dialects, then turns them into normalized AIS/PIS facts for Sorbet-Core.

**Current status: planning-only. No implementation code exists yet. See [ROADMAP.md](ROADMAP.md) and [docs/00-planning-brief.md](docs/00-planning-brief.md).**

## What Navesti is

Navesti is the **bank-driver layer** for Sorbet.

It translates bank-specific AIS/PIS APIs, payment statuses, balances, webhooks, and authorization flows into normalized facts. Each bank integration is expressed as a *dialect*: a compact, auditable description of what that bank's API means — its statuses, its mappings, its auth flow, its quirks — kept close to the bank's own documentation.

> We do not implement OMeta. We apply the OMeta/STEPS lesson: repeated integration mechanics become small, explicit, executable descriptions.

## What Navesti is not

Navesti does **not**:

- move money by itself
- decide compliance
- own ledger state
- own payment packet state
- retry or fail over payments
- persist anything (no database)
- render UI of any kind

It returns **normalized bank facts**. Sorbet-Core decides what those facts mean.

## How it relates to Sorbet-Core

Sorbet-Core is the protocol kernel: money packets, state machine, compliance, routing, ledger, idempotency, audit, webhooks/reconciliation, funding evidence, retry/failover, tenancy. Navesti duplicates none of that.

Navesti will eventually implement three Sorbet-Core ports — without ever importing Sorbet-Core:

```
Sorbet-Core
  -> Connectivity Port
  -> Navesti Adapter
  -> Bank / PSP / Rail

Sorbet-Core
  -> AIS BalanceProvider Port
  -> Navesti AIS Adapter
  -> Bank account data

Bank webhook
  -> Navesti Webhook Translator
  -> Sorbet-Core webhook ingestion
```

## Why headless

Banks own their login/SCA/authorization screens. Sorbet-Cockpit owns product UI. Navesti sits between them and owns neither: when a flow needs the user, Navesti returns an **interaction descriptor** (redirect URL, decoupled-poll instruction, QR payload) and the host decides how to present it. This keeps Navesti embeddable anywhere — a Rails app, a job worker, a future isolated service — with no rendering stack and no session state.

## First milestone

**Mock adapter + conformance suite.** A `MockNavesti` adapter that exercises every shape — AIS consent, balances, PIS submission, every status category, ambiguous timeouts, webhooks — and a conformance suite every future real adapter must pass. No real bank connector is built before the mock adapter proves the interfaces.

## Layout

| Path | Purpose |
|---|---|
| [CLAUDE.md](CLAUDE.md) | The rulebook for working in this repo |
| [ROADMAP.md](ROADMAP.md) | Phases 0–7 |
| [GLOSSARY.md](GLOSSARY.md) | Shared vocabulary |
| [docs/](docs/) | Planning documents (architecture, domain model, dialect language, …) |
| [docs/adr/](docs/adr/) | Architecture Decision Records |
