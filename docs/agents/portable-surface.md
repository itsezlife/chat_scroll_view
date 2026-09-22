# Portable surface

Standing policy for **packages**, **public APIs**, and **shipped docs** in this
repo. Apply it as the default — not as a fix after review.

## Portable default

Every library under repo-root `packages/`, the root `chat_scroll_view`
package, and any other standalone surface is **portable**: a foreign host may
depend on it alone, with no this-repo `example/`, screen, or product shell.

Design, name, and document for that host. Local demos and `.scratch/` specs
map product wiring; they do not define the portable contract.

## Naming

1. **Glossary first** — domain words come from the relevant `CONTEXT.md` (see
   [domain.md](domain.md)). Prefer glossary terms over near-synonyms the
   glossary marks _Avoid_.
2. **Roles in APIs** — package types, parameters, and dartdoc speak in roles
   (`host`, `scope`, `registry`, `policy`, `subject`), not example widget or
   route names.
3. **One meaning, one name** — if the glossary already owns a concept, reuse
   that token in code, tests, ADRs, and README prose.

## Docs

Shipped prose (dartdoc, package README, ADR body, OKF, architecture notes)
states **current contracts**: purpose, invariants, inputs/outputs, silent
paths, failure modes, when to use vs related APIs.

Voice, smells, and examples: [agnostic-documentation.md](agnostic-documentation.md).
Thin **app-local** notes may name routes or demo screens; portable surfaces
stay role-shaped.

## Done when

- [ ] A new reader with no chat history can apply the API from the docs alone
- [ ] Another app can adopt the package without renaming half the prose
- [ ] Names match glossary / roles; no example-only identifiers in the public surface
- [ ] Footguns that still exist are documented; archaeology and call-site tours are not
