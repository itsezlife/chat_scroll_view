# Domain Docs

How the engineering skills should consume this repo's domain documentation when exploring the codebase.

## Before exploring, read these

- **[`CONTEXT-MAP.md`](../../CONTEXT-MAP.md)** — which contexts exist and how they relate.
- **[`CONTEXT.md`](../../CONTEXT.md)** — Chat Scroll Viewport glossary. Glossary only; not a spec.
- **[`docs/panel-catalog/CONTEXT.md`](../panel-catalog/CONTEXT.md)** — Panel Catalog Viewport glossary (keyboard panel catalogs).
- **[`docs/architecture/index.md`](../architecture/index.md)** — OKF runtime constitution for chat scroll. Read **before** changing scroll, layout, day headers, or animations.
- **`docs/adr/`** — accepted policy:
  - [ADR 001: Message ID Scheme](../adr/001-message-id-scheme.md)
  - [ADR 002: Position Model](../adr/002-position-model.md)
  - [ADR 005: Stitch far path with navigation load-gate](../adr/005-stitch-far-path-and-load-gate.md) (Chat Scroll)
  - [ADR 006: Panel Catalog Viewport](../adr/006-panel-catalog-viewport.md)

Feature specs under `specs/` are incremental contracts. They do not replace the architecture bundle.

If a listed file is missing, **proceed silently**. Don't flag its absence; don't suggest creating it upfront. The `/domain-modeling` skill (reached via `/grill-with-docs` and `/improve-codebase-architecture`) creates glossary entries and ADRs lazily when terms or decisions actually get resolved.

## File structure

This is a **multi-context** repo:

```
/
├── CONTEXT-MAP.md
├── CONTEXT.md                         ← Chat Scroll Viewport glossary
├── docs/
│   ├── adr/                           ← system-wide / chat decisions
│   ├── architecture/                  ← chat scroll OKF constitution
│   └── panel-catalog/
│       └── CONTEXT.md                 ← Panel Catalog Viewport glossary
└── lib/
```

## Use the glossary's vocabulary

When your output names a domain concept (in an issue title, a refactor proposal, a hypothesis, a test name), use the term as defined in the **relevant** context glossary (`CONTEXT.md` or `docs/panel-catalog/CONTEXT.md`). Don't drift to synonyms the glossary explicitly avoids.

If the concept you need isn't in the glossary yet, that's a signal — either you're inventing language the project doesn't use (reconsider) or there's a real gap (note it for `/domain-modeling`).

## Flag ADR conflicts

If your output contradicts an existing ADR, surface it explicitly rather than silently overriding:

> _Contradicts ADR-0007 (event-sourced orders) — but worth reopening because…_
