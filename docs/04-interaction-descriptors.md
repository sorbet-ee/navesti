# 04 — Interaction Descriptors

How Navesti represents flow steps that require the user (PSU) or the bank's own UI — without rendering anything.

## Principle

> Navesti returns descriptors. Sorbet-Cockpit renders UX. Bank renders auth/SCA screens.

When a flow reaches a point only the PSU can advance (SCA, consent approval, app confirmation), Navesti stops and returns an `Interaction` value object describing *what kind of step it is* and *the data needed to present it*. Navesti never knows whether the host shows a button, a QR code on a kiosk, or a deep link in a mobile app.

## Types

| type | Meaning | Host's job | Completion signal |
|---|---|---|---|
| `:redirect` | PSU's browser must visit a bank URL and return | open `url`, handle the callback | host receives callback (code/state), calls the next adapter step |
| `:app_redirect` | Deep link into the bank's mobile app | open `url` on the device | app-to-app return URL, then next adapter step |
| `:decoupled` | PSU approves out-of-band (e.g. Smart-ID, bank app push) | tell the user to check their device; poll | poll the adapter until status changes |
| `:qr` | PSU scans a QR with the bank app | render `qr_payload` as a QR image | poll, as decoupled |
| `:poll` | No PSU action; bank just needs time | wait `poll_after`, then poll | poll until terminal status |
| `:none` | No interaction required, flow already complete | nothing | — |

## Shape (pseudo-code)

```ruby
Interaction(
  type:               :redirect,
  url:                "https://psd2.bank.example/auth?...",
  expires_at:         "2026-06-12T10:30:00Z",
  provider_reference: ProviderReference(:consent, "c-123", :mock_navesti),
  state:              "host-supplied-anti-forgery-token",
  poll_after:         nil,            # decoupled/qr/poll only
  qr_payload:         nil,            # qr only
  raw:                { ... }         # bank response this was derived from
)
```

Field rules:

- `url` required for `:redirect`/`:app_redirect`; `qr_payload` required for `:qr`; `poll_after` (duration or absolute time) required for `:decoupled`/`:qr`/`:poll`.
- `expires_at` always populated when the bank communicates a deadline — hosts need it for timeout UX, Sorbet-Core needs it for abandonment handling.
- `state`: the **host** generates anti-forgery state (it owns the callback endpoint); Navesti accepts it as input when building the URL and echoes it in the descriptor.

## Lifecycle example (redirect consent)

```
host: adapter.create_consent(...)            -> Consent(status: :received) + Interaction(:redirect, url:)
host: presents url; PSU authenticates at bank; bank redirects back with code
host: adapter.exchange_code(code, ...)       -> tokens (returned to host, not stored)
host: adapter.fetch_accounts(token)          -> [Account]
```

Navesti is stateless between these calls — every call carries what it needs (references, tokens) as arguments.

## Open questions

- Should `Interaction` carry a `next_step` hint (e.g. `:exchange_code`) so hosts don't hardcode flow order, or does that smuggle a flow engine in through the back door? Proposed: no hint in Phase 1; revisit during dialect extraction (Phase 6) with real adapters in hand.
- Multi-SCA flows (bank demands a second SCA mid-payment): represented as another Interaction returned from the submission/poll call. Conformance suite needs a mock case for this.
