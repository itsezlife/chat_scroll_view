# AGENTS.md

High-signal orientation for agents in **chat_scroll_view**. Read this first.
Deep detail stays behind pointers — do not treat this file as the constitution.

Monorepo: anchor-based **chat scroll** viewport (repo-root package) plus
portable libs under `packages/`. Example app is `example/` only.

## Commands

```shell
# Every gate CI runs: workspace lints, then analyze + tests per package in
# dependency order (resolves the workspace first)
scripts/check

# Root package (viewport) — message + text selection live here
flutter test
dart analyze --fatal-infos
```

Prefer package-local tests for the package you changed. Full-repo suites are
for integration claims, not every edit.

The repo is one **pub workspace** (one `pubspec.lock`, at the root); package-local
`flutter test` / `dart analyze` still work. Append a new package to the root
`workspace:` list (literal paths, no globs). `dependency_overrides` (local
`flutter_md` at `../md`) only works at the root.

Lint rules, the fake / adapter naming conventions they read, the per-package
`tool/check` hook and the legacy baseline: [scripts/README.md](scripts/README.md).

## Package map

| Path                                     | Role                                                                      | Reach when…                                                                      |
| ---------------------------------------- | ------------------------------------------------------------------------- | -------------------------------------------------------------------------------- |
| `lib/` (`chat_scroll_view`)              | Anchor viewport; **message selection** + **text selection**; span gesture | scroll, layout, selection membership, text subject/range, span                   |
| `packages/content_model`                 | Pure-Dart leaf: content key / descriptor / collection, data seams, `Observable`, fakes + contracts | content identity, sources, stores, rich text                    |
| `packages/chrome_foundation`             | Leaf: palette, token groups, theme scope, motion, strings, icons, glass   | theme, glass, motion, strings                                                    |
| `packages/catalog_assets`                | Asset cache, media pipeline seams, baked glyph atlas                      | paintables, readiness, budgets, atlas / bake                                     |
| `packages/panel_catalog`                 | Panel catalog viewport                                                    | emoji/sticker/GIF grid, section layout, leaf hit, snapshot                       |
| `packages/emoji_data` / `emoji_catalog_pack` | Emoji logic and glyph probe / generated catalog and keyword packs     | emoji search, variants, probe, generator                                         |
| `packages/kv_shared_preferences`         | `shared_preferences`-backed `KeyValueStore`                               | persistence adapter only                                                         |
| `packages/panel_shell` / `panel_pages` / `panel_presentation` | Panel shell + page registry / catalog pages / presentation kinds and policy | panel tabs, search, pages, popup / docked / keyboard replacement, occupancy |
| `packages/chat_composer`                 | Slot-based composer, input controller, entity text                        | composer slots, input, queries                                                   |
| `packages/chat_chrome`                   | Retiring: dissolved by [ADR 020](docs/adr/020-package-topology.md)        | only while it still exists; do not add to it                                     |
| `example/`                               | Demo host only — not the portable contract                                | wiring demos                                                                     |
| `scripts/`                               | `scripts/check` entry + the workspace lints (`workspace_check` package)   | CI gates, dependency direction, re-export / fakes rules                          |
| `tdesktop/`                              | Read-only Telegram Desktop reference checkout                             | desktop selection parity analysis                                                |
| `telegram-ios/`                          | Read-only Telegram-iOS sparse checkout                                    | iOS chat / selection parity analysis                                             |

## Selection (load-bearing)

**Selection policy** chooses mobile vs desktop/web entry, nesting, dismiss, and
Copy — not a universal “message-then-text” law. The viewport owns markdown
**text selection** ([ADR 013](docs/adr/013-viewport-owns-markdown-text-selection.md)).

| Branch                                                                                                                     | Doc                                                                 |
| -------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------- |
| Glossary (_Message selection_, _Text selection_, _Text selection subject_, _Selection policy_, _Selection interaction_, _Span yield_, _Inline hit_, _Body linkify_, _Linkify policy_, _Link preview_, _Tap highlight_, _Smooth text contour_, _Fenced code block header_) | [CONTEXT.md](CONTEXT.md)                                            |
| Fenced code blocks, cursors & press / tap highlight                                        | [ADR 014](docs/adr/014-fenced-code-interaction-and-smooth-contour-highlight.md)    |
| Engine-owned markdown text selection (supersedes optional bridge)                                                          | [ADR 013](docs/adr/013-viewport-owns-markdown-text-selection.md)    |
| Per-body scope owns continuous text gestures (yield after gate)                                                            | [ADR 015](docs/adr/015-per-body-scope-owns-continuous-text-gestures.md) |
| Body linkify host-invoked (not viewport paint)                                                                             | [ADR 017](docs/adr/017-body-linkify-host-invoked.md)                |
| Cross-platform policy (supersedes mobile-only ADR 010)                                                                     | [ADR 012](docs/adr/012-cross-platform-selection-policies.md)        |
| Mobile message-then-text path (historical; mobile strategy)                                                                | [ADR 010](docs/adr/010-message-then-text-selection.md)              |
| Span gesture (viewport-owned long-press)                                                                                   | [ADR 003](docs/adr/003-viewport-owned-span-gesture.md)              |
| Feature scratch (spec + issues)                                                                                            | [`.scratch/chat-md-selection/`](.scratch/chat-md-selection/spec.md) |
| Desktop reference behavior                                                                                                 | [tdesktop/REFERENCE.md](tdesktop/REFERENCE.md)                      |
| iOS reference behavior                                                                                                     | [telegram-ios/REFERENCE.md](telegram-ios/REFERENCE.md)              |

## Package architecture (load-bearing)

The package set and dependency direction are fixed by
[ADR 020](docs/adr/020-package-topology.md); a package it lists that is absent
from `packages/` has not landed yet. `scripts/check` enforces the rules.

| Branch                                                                                   | Doc                                                                   |
| ---------------------------------------------------------------------------------------- | --------------------------------------------------------------------- |
| Glossaries                                                                               | [Content and Assets](docs/content/CONTEXT.md), [Chat Chrome](docs/chrome/CONTEXT.md), [Panel Catalog](docs/panel-catalog/CONTEXT.md) |
| Content identity, collections                                                            | [ADR 021](docs/adr/021-content-identity-and-collections.md)           |
| Asset cache, media pipeline, glyph atlas                                                 | [ADR 022](docs/adr/022-asset-cache-and-media-pipeline.md)             |
| Data seams, catalog shipping, persistence                                                | [ADR 023](docs/adr/023-data-layering-and-persistence.md)              |
| Panel catalog public seams (amends ADR 006)                                              | [ADR 024](docs/adr/024-panel-catalog-seams.md)                        |
| Panel shell, pages, state ownership (supersedes parts of ADR 007)                        | [ADR 025](docs/adr/025-panel-shell-and-pages.md)                      |
| Composer                                                                                 | [ADR 026](docs/adr/026-composer-model.md)                             |
| Theme tokens, glass, motion                                                              | [ADR 027](docs/adr/027-foundation-theme-glass-motion.md)              |
| Panel presentation, occupancy, IME (supersedes the inset parts of ADR 007)               | [ADR 028](docs/adr/028-panel-presentation.md)                         |
| Host composition root, inline embeds                                                     | [ADR 029](docs/adr/029-host-integration.md)                           |
| Fakes, contracts, gates                                                                  | [ADR 030](docs/adr/030-testing-policy.md)                             |
| Strings, RTL, semantics, shortcuts                                                       | [ADR 031](docs/adr/031-localization-accessibility-and-input.md)       |

**Package invariants**

- No package re-exports another package's API; hosts import what they use.
- `content_model` and `chrome_foundation` depend on no workspace package.
- `panel_shell`, `panel_pages` and `panel_presentation` never depend on data
  payloads, codecs or fetchers; `panel_catalog` never depends on
  `chrome_foundation` and never imports atlas types.
- Fakes are exported only from `testing.dart`; production code never
  downcasts to a fake or a concrete cache.
- A leaf that fails keeps its placeholder: there is no visible failed stage.

**Invariants agents must not silently reverse**

- Character-range text stays **one message** in the chat list (no article-style
  multi-message ranges).
- Viewport owns markdown **text selection** (ADR 013); new work lands on the
  public selection facade in `chat_scroll_view`.
- Policy strategies are pure Dart (`$Mobile` / `$Desktop` shape) — not
  `_vm`/`_js` forks unless a real native/web spirit differs.
- Copy **feedback UI** is app-side; the facade exposes **selection
  interactions** (`ChatSelectionInteraction` via `onInteraction` /
  listeners), not Material toasts.
- **Body linkify** is host-invoked (send / materialize); the viewport never
  auto-detects bare URLs or mentions on paint ([ADR 017](docs/adr/017-body-linkify-host-invoked.md)).

## Domain and architecture

| Branch                                         | Doc                                                            |
| ---------------------------------------------- | -------------------------------------------------------------- |
| Contexts and relationships                     | [CONTEXT-MAP.md](CONTEXT-MAP.md)                               |
| Chat Scroll glossary                           | [CONTEXT.md](CONTEXT.md)                                       |
| Panel Catalog glossary                         | [docs/panel-catalog/CONTEXT.md](docs/panel-catalog/CONTEXT.md) |
| Content and Assets glossary                    | [docs/content/CONTEXT.md](docs/content/CONTEXT.md)             |
| Chat Chrome glossary                           | [docs/chrome/CONTEXT.md](docs/chrome/CONTEXT.md)               |
| Runtime constitution (scroll/layout/animation) | [docs/architecture/index.md](docs/architecture/index.md)       |
| How to consume domain docs                     | [docs/agents/domain.md](docs/agents/domain.md)                 |
| ADRs (policy)                                  | [docs/adr/](docs/adr/)                                         |

Read the architecture bundle **before** changing scroll, layout, day headers,
or animations. Read ADR 012 and ADR 013 **before** changing selection
entry/exit/Copy or text-selection ownership.

## Portable surface

Package APIs and shipped docs name **glossary** terms and **roles** (host,
scope, policy, subject). Contracts only — no product screen inventories.

- [docs/agents/portable-surface.md](docs/agents/portable-surface.md)
- [docs/agents/agnostic-documentation.md](docs/agents/agnostic-documentation.md)

## Issue tracker and triage

| Branch                                        | Doc                                                          |
| --------------------------------------------- | ------------------------------------------------------------ |
| `.scratch/<feature>/` specs + numbered issues | [docs/agents/issue-tracker.md](docs/agents/issue-tracker.md) |
| Status strings (`needs-triage` … `wontfix`)   | [docs/agents/triage-labels.md](docs/agents/triage-labels.md) |

## Agent skills (this repo)

| Skill                                      | When                                                            |
| ------------------------------------------ | --------------------------------------------------------------- |
| `think` (global: `~/.agents/skills/think/`) | Design / structure / Dart-Flutter canon before non-trivial code |
| `.claude/skills/control/`                  | Control-plane work as documented there                          |
| `.claude/skills/telegram-java-to-flutter/` | Porting from Telegram Android Java                              |

Think map: `~/.agents/skills/think/index.md`
(`foundation` + `patterns` always; `dart-flutter` when editing Dart).
Shared Agent Skills path — visible to Cursor, OpenCode, and other clients that load `~/.agents/skills/`.
