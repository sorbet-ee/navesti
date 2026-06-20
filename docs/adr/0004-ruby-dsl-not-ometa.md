# ADR-0004: Ruby DSL, not OMeta

## Status

Proposed

## Context

Navesti's design draws on OMeta and the VPRI STEPS work: small problem-oriented languages, pattern-directed transformation, chains of meaning, semantic compression. The temptation is to implement the machinery itself — a pattern-matching engine or parser generator in which bank dialects are grammars. An earlier iteration in this repo (`pre_gem` branches) already built a generic workflow engine and watched it absorb concerns (retries, branching policy) that belong elsewhere.

## Decision

**No OMeta implementation. No parser engine.** We use plain Ruby DSLs and tables, introduced only when they demonstrably simplify bank dialect expression — governed by the three-times rule: *when the same bank-specific shape appears three times, stop and name the language that would express it.* The DSL surface always evaluates eagerly to frozen plain-Ruby data (DSL-over-tables, docs/05).

## Consequences

Good:
- We keep the OMeta *lesson* (repeated mechanics become small explicit executable descriptions) without the engine cost.
- Dialects stay debuggable with ordinary Ruby tooling; no grammar layer to learn before auditing a bank integration.
- Vocabulary grows from evidence (three concrete occurrences), not speculation.

Bad:
- Some elegance lost: truly grammar-shaped problems (ISO 20022 XML, MT messages) would suit pattern-directed translation well; we'll handle them with libraries or explicit code instead.
- "Tiny DSL" discipline requires policing — DSLs creep one helpful feature at a time.

## Alternatives Considered

1. **Implement an OMeta-style engine** — maximum conceptual purity; a research project inside a payments deadline, and a bus-factor-one artifact.
2. **Adopt an existing parsing/transformation library as the core abstraction** — dependency-heavy, and bank APIs are mostly JSON-over-REST where a grammar buys little.
3. **No DSL at all, plain code forever** — readable per adapter but forfeits semantic compression; bank #7 becomes copy-paste #6.

## Open Questions

- Who approves a new DSL vocabulary word? (Default: an ADR-lite note in the PR citing the three occurrences.)
- Gate for revisiting pattern-directed translation if XML/ISO 20022 work makes it genuinely attractive (would require a new ADR).
