# Domain Docs

How the engineering skills should consume this repo's domain documentation when exploring the codebase.

## Before exploring, read these

- **[`CONTEXT.md`](../../CONTEXT.md)** — ubiquitous language for this viewport. Glossary only; not a spec.
- **[`docs/architecture/index.md`](../architecture/index.md)** — OKF runtime constitution. Read **before** changing scroll, layout, day headers, or animations.
- **`docs/adr/`** — ID scheme and position-model policy:
  - [ADR 001: Message ID Scheme](../adr/001-message-id-scheme.md)
  - [ADR 002: Position Model](../adr/002-position-model.md)

Feature specs under `specs/` are incremental contracts. They do not replace the architecture bundle.

If a listed file is missing, **proceed silently**. Don't flag its absence; don't suggest creating it upfront. The `/domain-modeling` skill (reached via `/grill-with-docs` and `/improve-codebase-architecture`) creates glossary entries and ADRs lazily when terms or decisions actually get resolved.

## File structure

This is a **single-context** repo:

```
/
├── CONTEXT.md                         ← glossary
├── docs/
│   ├── adr/                           ← accepted policy
│   │   ├── 001-message-id-scheme.md
│   │   └── 002-position-model.md
│   └── architecture/                  ← OKF runtime constitution
│       └── index.md
└── lib/
```

Multi-context layout (not used here; presence of `CONTEXT-MAP.md` at the root):

```
/
├── CONTEXT-MAP.md
├── docs/adr/                          ← system-wide decisions
└── src/
    ├── ordering/
    │   ├── CONTEXT.md
    │   └── docs/adr/                  ← context-specific decisions
    └── billing/
        ├── CONTEXT.md
        └── docs/adr/
```

## Use the glossary's vocabulary

When your output names a domain concept (in an issue title, a refactor proposal, a hypothesis, a test name), use the term as defined in `CONTEXT.md`. Don't drift to synonyms the glossary explicitly avoids.

If the concept you need isn't in the glossary yet, that's a signal — either you're inventing language the project doesn't use (reconsider) or there's a real gap (note it for `/domain-modeling`).

## Flag ADR conflicts

If your output contradicts an existing ADR, surface it explicitly rather than silently overriding:

> _Contradicts ADR-0007 (event-sourced orders) — but worth reopening because…_
