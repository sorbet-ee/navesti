# 09 — Webhooks

Navesti's webhook responsibility is **translation and verification**, nothing else.

> Navesti translates webhook payloads. Sorbet-Core stores webhook_events and decides applied / duplicate / unmatched / rejected / provider_conflict.

## Input

Exactly what the host's HTTP endpoint received, verbatim:

- `connector` — which dialect interprets these bytes
- `headers` — unmodified (signature headers, timestamps, event ids often live here)
- `raw body` — unmodified bytes (not pre-parsed JSON: signatures verify bytes)

Navesti has no HTTP endpoint of its own. The host terminates TLS, receives the POST, and hands the parts to Navesti synchronously.

## Pipeline

```
(connector, headers, raw_body)
  -> signature verification        (dialect declares scheme + key reference)
  -> parse                         (per dialect: JSON now, XML later)
  -> event id extraction           (header or body path per dialect; fingerprint fallback)
  -> provider reference extraction (the correlation key back to a submission/consent)
  -> status/event extraction       (event type + optional PaymentStatus via the status tables)
  -> payload fingerprint           (stable hash of canonical bytes)
  -> BankEvent                     (with raw evidence: headers + body, verbatim)
```

## Signature verification hook

- The dialect declares the scheme (`hmac_sha256` over body, JWS detached, none) and which header carries it.
- Keys/secrets are **supplied by the host per call or at adapter construction** — never stored by Navesti ([10-security-model.md](10-security-model.md)).
- Verification failure is a distinct typed outcome (`Navesti::SignatureVerificationFailed`, carrying raw evidence) — **not** a parse error and not a silently dropped event. Sorbet-Core decides whether to alert or reject.
- Phase 0 note: actual HMAC/JWS implementation is forbidden until Phase 7-adjacent work; the *interface* (verify → ok | failed) is what Phase 1 defines.

## Event id and duplicates

- `event_id` comes from the provider when one exists.
- When the bank sends none, `event_id` is derived from the payload fingerprint and marked `event_id_source: :fingerprint`.
- **Duplicate semantics are owned by Sorbet-Core.** Navesti's only duplicate-related guarantee: the same bytes always translate to the same `event_id` + `payload_fingerprint`, so Sorbet-Core's dedup has stable keys. A duplicate event id must still be parseable (conformance case).

## Payload fingerprint

Stable hash (e.g. SHA-256) over the raw body bytes plus the signature-relevant headers, computed identically on every call. Used by Sorbet-Core for dedup and provider-conflict detection (same event id, different payload).

## Polling-only banks

Some first-wave banks have no webhooks (capability `webhooks false`). The same `BankEvent` shape is produced by **status polling**: a poll that observes a status change emits a synthetic event with `event_id_source: :poll` and a fingerprint over the polled response. Sorbet-Core consumes one event stream regardless of transport. (Open question 9 in [13-open-questions.md](13-open-questions.md) — including who schedules the polling. Proposed: Sorbet-Core schedules, Navesti executes one poll per call.)

## Raw evidence

The BankEvent's `raw` carries headers + body byte-for-byte. Redaction applies to **logs**, not to evidence returned to the host (the host persists evidence in its own trust domain; see [10-security-model.md](10-security-model.md)).
