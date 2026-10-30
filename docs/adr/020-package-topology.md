# ADR 020: Package topology and dependency direction

The catalog, panel and composer code is split into a directed graph of small
packages. Two pure leaves (`content_model`, `chrome_foundation`) depend on
nothing; a third leaf, `composer_editable`, depends on the SDK only. The asset
cache, data layer, panel shell, pages, presentation and composer sit above
them. `chat_chrome` is dissolved and no package re-exports another package's
API.

**Status**: Accepted  
**Date**: 2026-10-16  
**Amended**: 2026-10-16 — change notification is `package:listen`, an external package every package that names its types declares for itself; it is not a workspace edge and is never re-exported ([ADR 023](023-data-layering-and-persistence.md) Amendment)  
**Amended**: 2026-10-18 — a `composer_editable` leaf (the composer's editable, [ADR 038](038-composer-editable-fork.md)), depended on by `chat_composer` only; the root `chat_scroll_view` package depends on `catalog_assets` and `content_model` (rows added and changed below; rule 6 added)  
**Amended**: 2026-10-31 — a `chat_wallpaper` leaf ([ADR 040](040-chat-wallpaper.md)); it depends on no workspace package and nothing in the workspace depends on it but the example  
**Relates to**: [ADR 006](006-panel-catalog-viewport.md) (package list in its Decided table is replaced by this one), [ADR 007](007-keyboard-panel-controller.md), [ADR 012](012-cross-platform-selection-policies.md)

## Decided

| Package | Role | Depends on |
| ------- | ---- | ---------- |
| `content_model` | Pure-Dart leaf (its only non-SDK dependencies are `meta` and `listen`, which are not workspace packages). Content identity, collections, data seams (`CollectionSource`, `SearchSource`, `RecentsStore`, `PreferenceStore`, `KeywordSource`, `GlyphSupport`, `KeyValueStore`, `ContentResolver`, `RichClipboard`), reference stores, fakes and contract suites, the inline content ref and the rich-text value, opt-in `markdown.dart` | none |
| `chrome_foundation` | Leaf. Palette, token groups, theme scope, motion roles, strings scope, icon registry, glass. Nothing chat-specific | none |
| `catalog_assets` | Asset cache core: paintable, spec and profile, staged readiness, tiered LRU, playback clock, fetcher and decoder seams, baked glyph atlas, scope, content embed | `content_model` |
| `panel_catalog` | Catalog viewport. Public seams per [ADR 024](024-panel-catalog-seams.md) | `content_model`, `catalog_assets` |
| `emoji_data` | Emoji-specific logic only: structure and keyword loaders, emoji `CollectionSource`, merged search, variants, pure-Dart glyph probe. No assets, no native code | `content_model` |
| `emoji_catalog_pack` | Catalog structure and per-locale keyword pack assets, plus the pinned generator under `tool/` | `content_model` |
| `kv_shared_preferences` | `shared_preferences`-backed `KeyValueStore` adapter | `content_model` |
| `chat_wallpaper` | Leaf. The chat wallpaper: value model and codec, freeform renderer and keyframes, motion, view, warm-up, service fills ([ADR 040](040-chat-wallpaper.md)). Pattern artwork is the host's | none (`flutter`, `vector_graphics`, `equatable`) |
| `rich_clipboard` | `RichClipboard` adapter: the HTML codec and the platform clipboard code, the workspace's one Flutter plugin package ([ADR 032](032-rich-clipboard.md)) | `content_model` |
| `panel_shell` | Host-independent panel: page registry, shell controller, pager, type tabs, bottom bar, search field, panel events, page scroll activity, focus and shortcuts | `chrome_foundation`, `content_model` |
| `panel_pages` | Catalog page scaffold and per-kind policies. Emoji page now; sticker and GIF pages later | `panel_shell`, `panel_catalog`, `catalog_assets`, `content_model`, `chrome_foundation` |
| `panel_presentation` | Sealed presentation kinds, the `$Mobile` / `$Desktop` policy, the presentation controller, occupancy, IME arbitration | `panel_shell`, `chrome_foundation` |
| `composer_editable` | Leaf. The composer's one editable: a renamed, patched copy of the Flutter framework's text field, editable text and selection overlay, with the touch gesture matrix, handle and magnifier motion and the toolbar fade ([ADR 038](038-composer-editable-fork.md)). Nothing chat-specific | none (`flutter` and `characters` only) |
| `chat_composer` | Slot-based composer, input-only controller, entity-aware text controller with formatting commands, selection menu, input query; renders through `composer_editable` | `chrome_foundation`, `content_model`, `catalog_assets`, `composer_editable` |
| `chat_scroll_view` (repo root) | The anchor viewport and its markdown bodies: message and text selection, inline hits, the embed adapter, spoiler wiring, `ChatEmojiBody`. Consumes the markdown engine fork by git ref ([ADR 035](035-markdown-engine-fork.md)), which is not a workspace package | `catalog_assets`, `content_model` |

Codec and fetcher adapters (Lottie, WebM, WebP, network, disk) are separate
packages created when needed. They depend on `catalog_assets`; the host wires
them. Landed: `image_decoder` (the engine's image codecs: stills and animated
WebP / GIF).

Rules, enforced by the dependency lint in `scripts/check` ([ADR 030](030-testing-policy.md)):

1. The graph is a DAG. `content_model`, `chrome_foundation` and `composer_editable` depend on no workspace package.
2. No package re-exports another package's API. A host imports what it uses.
3. `panel_shell`, `panel_pages` and `panel_presentation` never depend on data payloads (`emoji_catalog_pack`), codecs or fetchers.
4. Fakes are exported only from a package's `testing.dart` and never used by production code.
5. `panel_catalog` does not depend on `chrome_foundation`. Pages adapt tokens.
6. `composer_editable` is a leaf with `chat_composer` as its only dependent. A host reaches the field through the composer view, never the raw editable.

`chat_chrome` has no successor and there is no umbrella package. The inset
arbiter is not a shared leaf: it is a property of the keyboard-replacement
presentation ([ADR 028](028-panel-presentation.md)).

## Why

- Telegram splits a host-independent content widget from per-platform hosts. Desktop has `TabbedSelector` (content) with `TabbedPanel` (anchored popup) and `TabbedSection` (docked) as hosts; iOS has `EntityKeyboardComponent` and `ChatInputNode`. Only the mobile hosts arbitrate insets.
- The old `chat_chrome` fused content and the mobile host, bundled six separable layers, re-exported `emoji_data`, and had a composer and panel file cycle.
- Glass, theme and motion import nothing from composer, panel or data code, so they stand alone as a leaf.
- Message bodies that show inline custom emoji need identity and an asset binding only. `content_model` keeps them off the panel and data packages.
- A forked framework editable (about 15 000 lines with its own tests and an SDK re-vendor chore) needs its own boundary; folding it into the composer would put framework internals in a package whose job is slots and entities.
- Heavy payload and native dependencies (catalog assets, codecs) must not reach consumers that only need seams.

## Rejected

| Alternative | Why not |
| ----------- | ------- |
| Inset arbiter as a shared leaf under composer and panel | It is a mobile presentation concern; desktop and web have no equivalent |
| One package per presentation (`panel_mobile`, `panel_desktop`) | Web and narrow desktop must choose one at run time; strategies in one package match [ADR 012](012-cross-platform-selection-policies.md) |
| Pages inside the shell, or one package per page kind | The shell loses its host and kind independence, or each page package repeats the catalog viewport glue |
| Keeping `emoji_data` whole, or all codecs inside the asset package | Payload and native dependencies reach every consumer |
| `chat_chrome` as a thin umbrella | Re-exports hide the graph and defeat the dependency lint |

## Related

- Glossary: [Content and assets](../content/CONTEXT.md), [Chat chrome](../chrome/CONTEXT.md), [Panel Catalog](../panel-catalog/CONTEXT.md)
- Context map: [CONTEXT-MAP.md](../../CONTEXT-MAP.md)
- Lint rules and conventions: [scripts/README.md](../../scripts/README.md)
