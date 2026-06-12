# GLOSSARY

Short, precise definitions of the vocabulary used across Navesti docs.

**AIS** — Account Information Services. Read-only access to a bank account: accounts, balances, transactions. Requires PSU consent.

**PIS** — Payment Initiation Services. Initiating a credit transfer from a PSU's account at their bank.

**ASPSP** — Account Servicing Payment Service Provider. The bank that holds the account (e.g. LHV).

**TPP** — Third Party Provider. The regulated party calling the bank's API. Sorbet (or its licensed partner) is the TPP.

**PSU** — Payment Service User. The human or business that owns the bank account and authorizes access.

**SCA** — Strong Customer Authentication. The bank-side step where the PSU proves identity (Smart-ID, app approval, etc.). Always rendered by the bank, never by Navesti.

**Consent** — A bank-side grant allowing AIS access to specific accounts for a period. Has an id, scope, status, and expiry.

**Payment order** — The normalized instruction Navesti receives from the host: debtor, creditor, amount_minor, currency, rail, reference. Input, not state.

**Payment submission** — The fact that a payment order was submitted to a specific bank, with the bank's provider reference and initial status. Output, not state.

**Provider reference** — The bank's own identifier for a resource (payment id, consent id). The correlation key between submissions, polls, and webhooks.

**Interaction descriptor** — A normalized, render-free description of a step that needs the PSU or the bank's UI: a redirect URL, a decoupled-approval poll, a QR payload. Navesti returns descriptors; hosts render them.

**Redirect flow** — SCA via browser redirect to the bank and back.

**Decoupled flow** — SCA approved out-of-band (e.g. bank's mobile app); the TPP polls for completion.

**App-to-app flow** — Redirect that deep-links directly into the bank's mobile app and back to the calling app.

**Bank dialect** — The compact, declarative description of what one bank's API *means*: capabilities, status mappings, field mappings, auth profile, quirks. The unit of integration in Navesti.

**Capability** — A machine-readable claim in a dialect: supports AIS, supports SEPA instant, supports webhooks, supported interaction types.

**Raw evidence** — The unmodified provider payload (body, relevant headers, timestamps) attached to every normalized fact. Preserved verbatim; persisted by the host, never by Navesti.

**Normalized fact** — A bank-specific response translated into Navesti's canonical vocabulary, with raw evidence attached. Facts state what the bank said, not what it means for business state.

**side_effect_possible** — Boolean on payment outcomes: could money have moved (or still move) as a result of this attempt? Drives Sorbet-Core's safety decisions. Never false unless the bank explicitly guaranteed no side effect.

**Ambiguous outcome** — We cannot know whether the bank acted: timeout, transport failure after the request may have left, conflicting signals. Always `side_effect_possible: true`.

**Explicit rejection** — The bank affirmatively refused the request. `rejected`, `side_effect_possible: false`.

**Webhook event** — A bank-pushed notification, translated by Navesti into a normalized BankEvent (event id, provider reference, type, occurred_at, status, raw evidence). Deduplication and application are Sorbet-Core's job.

**Conformance suite** — The shared contract tests every adapter must pass. The executable definition of what "being a Navesti adapter" means.
