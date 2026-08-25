# ADR 006: Panel Catalog Viewport (sibling to Chat Scroll)

Keyboard-panel emoji / stickers / GIFs get their own **Panel Catalog Viewport** —
a thin extent-scroll RenderObject engine with paint leaves and Telegram-style
**stitch** far jumps — not `SuperSliverList` forever and not a fork of Chat
Scroll’s message-id / anchor model. Assets live in a **global catalog asset
cache** shared with chat; catalog DS notifies like `ChatDataSource` but does
not own decode bytes. Monorepo: root `packages/` (`catalog_assets`,
`panel_catalog`, `emoji_data`, `chat_chrome`); `chat_scroll_view` remains at
repo root.

**Status**: Accepted  
**Date**: 2026-08-24

## Decided

| Topic | Decision |
| ----- | -------- |
| Context | Sibling **Panel Catalog Viewport** ([glossary](../panel-catalog/CONTEXT.md)); not “Media Grid” (collides with chat attachments) |
| Ownership | Viewport = catalog body only; chrome around it is **KeyboardPanel** (ADR 007; was “catalog shell”) = strip / search / tabs / pickers / DS wiring |
| Geometry | **Extent scroll** (absolute offset + known/estimated content height) |
| Leaves | **Paint leaf** pool + **viewport-owned hit-test**; no per-cell StatefulWidget default |
| Leaf gestures | Tap and long-press start/move/end callbacks to **KeyboardPanel** with [CatalogLeaf] identity; optional **long-press eligibility** predicate; **fling-cancel suppress**; painted press scale + list-selector highlight |
| Theme | **[PanelCatalogTheme]** + **[PanelCatalogThemeData]** — package inherited theme for placeholder fill and press chrome; [PanelCatalogThemeData.lerp] for transitions |
| Placeholders | Kind-specific: **circle** (unicode), **thumb-first** (animated), **shaped wash** (stickers) — see [leaf-placeholder.md](../panel-catalog/leaf-placeholder.md) |
| Far path | [CatalogFarStitch] when not attached and flat-row distance `> 9` (Telegram `spanCount × 9` in per-cell adapter space; or animations off). Capture → teleport → dual-translate; not naked `jumpTo` |
| Near path | [PanelCatalogController.jumpToSection] + [CatalogNearScroll] (220ms decelerate; Telegram `LinearSmoothScrollerCustom` parity). Landing under viewport [padding.top] |
| Section jump | Flat-row gate ([kFarPathDistanceGateFactor] = 9 rows, not `span × 9`); [isSectionJumpActive] for shell strip-sync gating; near writes silent [correctOffset] only |
| Assets | **Global catalog asset cache** (`packages/catalog_assets`); panel + chat bind/paint only |
| Data | Parallel catalog DS + `addDataListener` / `notifyDataChanged`; fetch not in the viewport |
| v1 ship | Unicode catalog + stitch + paint leaves; leaf contract ready for document-backed / animated |
| Packages | Root `packages/` for catalog + chrome/data; `example/` is the app; `chat_scroll_view` remains at repo root |

## Rejected

| Alternative | Why not |
| ----------- | ------- |
| Extend Chat Scroll glossary / anchor origin | Wrong identity model for a sectioned catalog |
| Far path = `jumpTo` | Breaks Telegram parity (`RecyclerAnimationScrollHelper` stitch) |
| One generic shimmer for all leaves | Telegram uses three different loading paints |
| Panel-private drawable cache | Blocks reuse in chat inline emoji / stickers / GIFs |
| Engine inside `chat_scroll_view` or forever under `example/packages` | Wrong bounded context; hides shared product surface |
| Big-bang move of chat into `packages/` with v1 | Unrelated churn; defer |

## Related

- Chat stitch / load-gate: [ADR 005](005-stitch-far-path-and-load-gate.md) (chat-only rules; panel does **not** inherit message load-gate by default)
- Context map: [CONTEXT-MAP.md](../../CONTEXT-MAP.md)
