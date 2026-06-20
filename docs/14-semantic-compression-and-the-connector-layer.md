# 14 — Semantic compression and the connector layer

> Research capture + working plan. Records what the OMeta / VPRI STEPS work
> actually teaches, maps it onto Navesti's current code, and fixes the plan for
> *when* and *how* we compress the per-bank connector. Decision lineage:
> [ADR-0004 — Ruby DSL, not OMeta](adr/0004-ruby-dsl-not-ometa.md). This note
> does not change ADR-0004; it operationalizes it.

## Why this note exists

The LHV connector is ~1,000 LoC for **one** bank (`adapter` 376, `mappers` 348,
`config` 151, `dialect` 128). That is large for a "dialect." This note explains
why, what is actually compressible, and the discipline that decides when we act.

## What OMeta and STEPS actually teach

**OMeta** (Warth & Piumarta, VPRI, DLS'07) is PEG pattern-matching generalized
from text to **arbitrary structured data** — ASTs, JSON, domain objects. Its
leverage: semantic actions inline (match + transform in one rule), parameterized
/ higher-order rules, grammar inheritance & specialization, and pattern-match
over structure that binds fields by shape. The one-line reason it compresses:
**procedural code describes control flow; a grammar describes structure** — the
generic engine supplies the "how" (traversal, backtracking, memoization), so you
write only the "what". Reported compression over hand-written transformers: ~5–10×.

**STEPS** (VPRI NSF reports, TR-2011-004 / TR-2012-001) rebuilt a whole personal
computing stack in ~20,000 LoC by making **the code read like the problem's own
description**: Gezira vector graphics in ~400–500 lines of the "runnable math"
language Nile; a TCP/IP stack as state machines in ~200 lines.

**The discipline is the load-bearing part, and it constrains us:**

> Write the naive solution first. Design the language only after you understand
> the domain deeply. *Premature DSL design is as dangerous as premature
> optimization* — a bad DSL is a new liability, not a compression.

This is exactly our rulebook's "three-times" rule and ADR-0004. We keep the
OMeta **lesson** (repeated mechanics → small explicit executable descriptions)
and refuse the OMeta **engine** (no parser/pattern-matching machinery; plain
Ruby tables + tiny DSLs, eagerly evaluated to frozen data — docs/05, docs/07).

## Why the LHV connector is big: per-file analysis

| File | LoC | What it is | Compressible? |
|---|---:|---|---|
| `adapter.rb` | 376 | one method per operation: build headers → optional headers → request → guard → map | **Yes.** Every op is the same shape `(verb, url, required headers, optional headers, body, guard, mapper)` — a table, written out longhand. |
| `mappers.rb` | 348 | response JSON → value objects, field by field, + evidence/error/link wrapping | **Yes — OMeta's exact sweet spot.** Mapping is pattern-match-over-structured-data (`resourceId ?? iban → provider_account_id`). A declared source→target map + one generic applier replaces most of it. |
| `dialect.rb` | 128 | raw status/enum string → `(symbol, safety, side_effect)` | **Already a table.** This is the part that already applies the lesson; it is the model for the rest. |
| `config.rb` | 151 | per-endpoint URL builders + the SSRF-pinned `absolute()` | Endpoints → a table; `absolute()` is shared security infra, keep as code. |

Roughly **700+ of the ~1,000 "LHV" lines are mechanics that want to be
declarations**, not bank-specific logic. The irreducible parts — raw-evidence
preservation, redaction, SSRF link-pinning, deterministic idempotency UUID — are
**shared scaffolding** (the ~1,130 LoC outside `providers/`), paid once, not per
bank. `dialect.rb` already shows the target form; `adapter` and `mappers` do not
yet.

## Decision: defer extraction until Wise, then the third forces it

We have **one** instance. You do not abstract from one example — that is the
premature-DSL trap STEPS names explicitly. Therefore:

1. **Build Wise straightforwardly** as the second provider quartet (config /
   dialect / mappers / adapter), mirroring LHV. Do **not** generalize while
   writing it.
2. **Instrument, don't abstract.** Keep the *watch-list* below as a running
   record of which mechanics come out identical vs. genuinely bank-specific.
3. **Extract after Wise**, when the same shape has appeared the third time
   (≈ connector #3 / mock), into plain-Ruby tables + a tiny operation/mapping
   DSL — **never** an OMeta engine (ADR-0004). Target: a new bank ≈ a
   declaration file + a few custom handlers. Any move toward a parser/engine
   requires a new ADR.

Wise is a deliberately good discriminator: it is **UK OBIE 3.1.11**, not Berlin
Group, so it separates "PSD2-family mechanics" from "LHV quirks."

## The compression watch-list (fill in while building Wise)

Mechanics expected to be **identical** across LHV and Wise → future table/DSL:

- **Operation envelope** — assemble headers, attach optional headers
  conditionally, `@http.request`, `guard_response!`, hand to a mapper.
- **Evidence** — wrap every response as `{status, headers, body, captured_at}`,
  redacting secret-bearing bodies (token responses).
- **Error rejection** — find the provider's error object, raise a typed,
  redaction-safe `ProviderError` carrying the provider code.
- **Status/enum tables** — raw code → `(symbol, safety, side_effect)`; "unknown
  never collapses to a safe value."
- **Field mapping** — source path (+ fallback + transform) → value-object field,
  with raw preserved.
- **Link/URL safety** — resolve HATEOAS/redirect links pinned to origin + API
  root (`config.absolute`).

Mechanics expected to be **genuinely bank-specific** → stay as custom handlers
(and tell us what the DSL must *parameterize*, not absorb):

- **Auth model.** LHV: one OAuth token; consent created with it via
  `TPP-Redirect-URI` header. Wise OBIE: a `client_credentials` *app* token to
  create the consent, then a **Hybrid Flow** authorize with a **signed JWT
  request object** (`request=` param, PS256, `openbanking_intent_id`=ConsentId),
  then an `authorization_code` exchange yielding access + refresh tokens.
- **Request-object / id_token signing (JWS).** New shared capability LHV never
  needed (QWAC only, no QSEAL). OBIE requires PS256 signing + an `id_token`
  (JWS) to validate at callback. Build a minimal stdlib-OpenSSL JWS signer
  (sibling to `security/certificate_identity`), not a per-bank one-off.
- **Payload envelope.** LHV: flat Berlin Group JSON. Wise: the OBIE `{ "Data":
  { … }, "Risk": { … } }` envelope, nested `Account[]` with OBIE `SchemeName`/
  `Identification`. The mapping DSL must support different *source-path shapes*,
  not assume LHV's.
- **Consent model.** LHV: `availableAccounts` enum. Wise: a `Permissions[]` list
  (`ReadAccountsBasic`, `ReadBalances`, `ReadTransactions*`, …) and a consent
  `Status` lifecycle (`AwaitingAuthorisation` → authorised).

## References

- OMeta — [VPRI TR-2007-003 (PDF)](https://tinlizzie.org/VPRIPapers/tr2007003_ometa.pdf),
  [DLS'07 paper](https://dl.acm.org/doi/pdf/10.1145/1297081.1297086),
  [Warth thesis](https://web.cs.ucla.edu/~todd/theses/warth_dissertation.pdf)
- STEPS — [TR-2012-001 final report (PDF)](https://tinlizzie.org/VPRIPapers/tr2012001_steps.pdf),
  [TR-2011-004](http://archive.rickardlindberg.me/writing/alan-kay-notes/tr2011004_steps11.pdf)
- Piumarta & Warth — [Open, Extensible Object Models (PDF)](https://gwern.net/doc/cs/lisp/2008-piumarta.pdf)
- Ford — [Parsing Expression Grammars, POPL'04 (PDF)](https://bford.info/pub/lang/peg.pdf),
  [Packrat parsing](https://bford.info/packrat/)
- Internal: [ADR-0004](adr/0004-ruby-dsl-not-ometa.md),
  [docs/05 bank-dialect-language](05-bank-dialect-language.md),
  [docs/07 mapping-language](07-mapping-language.md)
