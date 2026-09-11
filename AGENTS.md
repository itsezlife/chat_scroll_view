# AGENTS.md

High-signal orientation for agents in **chat_scroll_view**. Read this first.
Deep detail stays behind pointers — do not treat this file as the constitution.

Monorepo: anchor-based **chat scroll** viewport (repo-root package) plus
portable libs under `packages/`. Example app is `example/` only.

## Commands

```shell
# Root package (viewport)
flutter test
dart analyze --fatal-infos

# Bridge (when touching markdown text selection)
cd packages/chat_md_selection && flutter test && dart analyze lib test
```

Prefer package-local tests for the package you changed. Full-repo suites are
for integration claims, not every edit.

## Package map

| Path | Role | Reach when… |
|---|---|---|
| `lib/` (`chat_scroll_view`) | Anchor viewport, message selection, span gesture, yield seam | scroll, layout, selection membership, span |
| `packages/chat_md_selection` | Optional markdown **bridge**: text selection orchestration + **selection policy** | message↔text selection, Copy, yield→range |
| `packages/chat_chrome` | Host chrome (keyboard panel, bars) | panel / chrome, not viewport geometry |
| `packages/panel_catalog` | Panel catalog viewport | emoji/sticker/GIF grid |
| `packages/catalog_assets` / `emoji_data` | Shared catalog assets / emoji data | leaf assets, not chat scroll origin |
| `example/` | Demo host only — not the portable contract | wiring demos |
| `tdesktop/` | Read-only Telegram Desktop reference checkout | desktop selection parity analysis |

## Selection (load-bearing)

**Selection policy** chooses mobile vs desktop/web entry, nesting, dismiss, and
Copy — not a universal “message-then-text” law.

| Branch | Doc |
|---|---|
| Glossary (*Message selection*, *Text selection*, *Text selection subject*, *Selection policy*) | [CONTEXT.md](CONTEXT.md) |
| Cross-platform policy (supersedes mobile-only ADR 010) | [ADR 012](docs/adr/012-cross-platform-selection-policies.md) |
| Mobile message-then-text path (historical; mobile strategy) | [ADR 010](docs/adr/010-message-then-text-selection.md) |
| Span yield / viewport owns long-press | [ADR 003](docs/adr/003-viewport-owned-span-gesture.md) |
| Bridge package boundary (core stays markdown-agnostic) | [ADR 011](docs/adr/011-markdown-selection-bridge.md) |
| Feature scratch (spec + issues) | [`.scratch/chat-md-selection/`](.scratch/chat-md-selection/spec.md) |
| Desktop reference behavior | [tdesktop/REFERENCE.md](tdesktop/REFERENCE.md) |

**Invariants agents must not silently reverse**

- Character-range text stays **one message** in the chat list (no article-style
  multi-message ranges).
- Core viewport stays **markdown-agnostic**; markdown selection lives in the
  bridge (ADR 011).
- Policy strategies are pure Dart (`$Mobile` / `$Desktop` shape) — not
  `_vm`/`_js` forks unless a real native/web spirit differs.
- Copy **feedback UI** is app-side; the bridge exposes Copy success
  observation (listeners + optional callback), not Material toasts.

## Domain and architecture

| Branch | Doc |
|---|---|
| Contexts and relationships | [CONTEXT-MAP.md](CONTEXT-MAP.md) |
| Chat Scroll glossary | [CONTEXT.md](CONTEXT.md) |
| Panel Catalog glossary | [docs/panel-catalog/CONTEXT.md](docs/panel-catalog/CONTEXT.md) |
| Runtime constitution (scroll/layout/animation) | [docs/architecture/index.md](docs/architecture/index.md) |
| How to consume domain docs | [docs/agents/domain.md](docs/agents/domain.md) |
| ADRs (policy) | [docs/adr/](docs/adr/) |

Read the architecture bundle **before** changing scroll, layout, day headers,
or animations. Read ADR 012 **before** changing selection entry/exit/Copy.

## Portable surface

Package APIs and shipped docs name **glossary** terms and **roles** (host,
scope, policy, subject). Contracts only — no product screen inventories.

- [docs/agents/portable-surface.md](docs/agents/portable-surface.md)
- [docs/agents/agnostic-documentation.md](docs/agents/agnostic-documentation.md)

## Issue tracker and triage

| Branch | Doc |
|---|---|
| `.scratch/<feature>/` specs + numbered issues | [docs/agents/issue-tracker.md](docs/agents/issue-tracker.md) |
| Status strings (`needs-triage` … `wontfix`) | [docs/agents/triage-labels.md](docs/agents/triage-labels.md) |

## Agent skills (this repo)

| Skill | When |
|---|---|
| `.cursor/skills/think/` | Design / structure / Dart-Flutter canon before non-trivial code |
| `.cursor/skills/control/` | Control-plane work as documented there |
| `.cursor/skills/telegram-java-to-flutter/` | Porting from Telegram Android Java |

Project think map: [`.cursor/skills/think/index.md`](.cursor/skills/think/index.md)
(`foundation` + `patterns` always; `dart-flutter` when editing Dart).
