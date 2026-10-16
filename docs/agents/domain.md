# Domain Docs

How the engineering skills should consume this repo's domain documentation when exploring the codebase.

## Before exploring, read these

- **[`CONTEXT-MAP.md`](../../CONTEXT-MAP.md)** — which contexts exist and how they relate.
- **[`CONTEXT.md`](../../CONTEXT.md)** — Chat Scroll Viewport glossary. Glossary only; not a spec.
- **[`docs/panel-catalog/CONTEXT.md`](../panel-catalog/CONTEXT.md)** — Panel Catalog Viewport glossary (keyboard panel catalogs).
- **[`docs/content/CONTEXT.md`](../content/CONTEXT.md)** — Content and Assets glossary (content identity, collections, data seams, asset cache).
- **[`docs/chrome/CONTEXT.md`](../chrome/CONTEXT.md)** — Chat Chrome glossary (theme and glass, panel shell and pages, presentation, composer).
- **[`docs/architecture/index.md`](../architecture/index.md)** — OKF runtime constitution for chat scroll. Read **before** changing scroll, layout, day headers, or animations.
- **`docs/adr/`** — accepted policy:
  - [ADR 001: Message ID Scheme](../adr/001-message-id-scheme.md)
  - [ADR 002: Position Model](../adr/002-position-model.md)
  - [ADR 003: Viewport owns the span gesture](../adr/003-viewport-owned-span-gesture.md) (Chat Scroll)
  - [ADR 005: Stitch far path with navigation load-gate](../adr/005-stitch-far-path-and-load-gate.md) (Chat Scroll)
  - [ADR 006: Panel Catalog Viewport](../adr/006-panel-catalog-viewport.md)
  - [ADR 009: Center Band vs Anchor origin](../adr/009-center-band.md) (Chat Scroll)
  - [ADR 010: Message-then-text (mobile policy; superseded)](../adr/010-message-then-text-selection.md) (Chat Scroll)
  - [ADR 011: Markdown text selection bridge package (superseded)](../adr/011-markdown-selection-bridge.md) (Chat Scroll)
  - [ADR 012: Cross-platform selection policies](../adr/012-cross-platform-selection-policies.md) (Chat Scroll)
  - [ADR 013: Viewport owns markdown text selection](../adr/013-viewport-owns-markdown-text-selection.md) (Chat Scroll)
  - [ADR 020: Package topology and dependency direction](../adr/020-package-topology.md)
  - [ADR 021: Content identity and collections](../adr/021-content-identity-and-collections.md) (Content and Assets)
  - [ADR 022: Asset cache and media pipeline](../adr/022-asset-cache-and-media-pipeline.md) (Content and Assets)
  - [ADR 023: Data layering and persistence](../adr/023-data-layering-and-persistence.md) (Content and Assets)
  - [ADR 024: Panel catalog public seams](../adr/024-panel-catalog-seams.md) (Panel Catalog)
  - [ADR 025: Panel shell and pages](../adr/025-panel-shell-and-pages.md) (Chat Chrome)
  - [ADR 026: Composer model](../adr/026-composer-model.md) (Chat Chrome)
  - [ADR 027: Foundation theme, glass and motion](../adr/027-foundation-theme-glass-motion.md) (Chat Chrome)
  - [ADR 028: Panel presentation](../adr/028-panel-presentation.md) (Chat Chrome)
  - [ADR 029: Host integration](../adr/029-host-integration.md)
  - [ADR 030: Testing policy](../adr/030-testing-policy.md)
  - [ADR 031: Localization, accessibility and input](../adr/031-localization-accessibility-and-input.md)

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
│   ├── panel-catalog/
│   │   └── CONTEXT.md                 ← Panel Catalog Viewport glossary
│   ├── content/
│   │   └── CONTEXT.md                 ← Content and Assets glossary
│   └── chrome/
│       └── CONTEXT.md                 ← Chat Chrome glossary
└── lib/
```

## Use the glossary's vocabulary

When your output names a domain concept (in an issue title, a refactor proposal, a hypothesis, a test name), use the term as defined in the **relevant** context glossary (`CONTEXT.md`, `docs/panel-catalog/CONTEXT.md`, `docs/content/CONTEXT.md` or `docs/chrome/CONTEXT.md`). Don't drift to synonyms the glossary explicitly avoids.

If the concept you need isn't in the glossary yet, that's a signal — either you're inventing language the project doesn't use (reconsider) or there's a real gap (note it for `/domain-modeling`).

Package and public-API naming also follow [portable-surface.md](portable-surface.md).

## Flag ADR conflicts

If your output contradicts an existing ADR, surface it explicitly rather than silently overriding:

> _Contradicts ADR-0007 (event-sourced orders) — but worth reopening because…_
