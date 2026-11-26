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
**Amended**: 2026-11-05 — a `golden_baseline` leaf: test support for golden tests ([ADR 030](030-testing-policy.md) Amendment), declared by any member under `dev_dependencies:` only; such a dev dependency does not make a leaf stop being one (rule 7)  
**Amended**: 2026-11-06 — `lottie_native`, `lottie_decoder`, `video_native` and `video_decoder` ([ADR 042](042-native-media-decoding.md)); the native packages are leaves, rule 8 added  
**Amended**: 2026-11-08 — `frame_texture` ([ADR 043](043-platform-texture-frames.md))  
**Amended**: 2026-11-09 — a `swipe_pager` leaf: the horizontal pager with the reference mobile client's swipe rules, depended on by `panel_shell`; held by convention (the dependency lint is not extended for it)  
**Amended**: 2026-11-09 — `content_model` gains the `PackSource`, `ContentLibrary` and `LibraryStorage` seams; `panel_pages` holds the content preview and the pack sheets ([ADR 044](044-content-library-packs-and-preview.md)); no edge changes  
**Amended**: 2026-11-09 — a `bulletins` package: transient notices over a surface ([ADR 045](045-bulletins.md)), depending on `chrome_foundation` only; held by convention (the dependency lint is not extended for it)  
**Amended**: 2026-11-12 (native-media tickets 218, 220) — a `viewport_scroll` leaf: the scroll physics (value, fling runner, edge-effect seam and strategies, formerly the root package's `ChatScrollPhysics` family, renamed `ViewportScrollPhysics`) and the keyboard scroll keys, depended on by the root package and `panel_catalog` (the panel catalogue scrolls as the chat does) and by `panel_pages` (its keys); held by convention (the dependency lint is not extended for it)
**Amended**: 2026-11-13 (media-pipeline ticket 08) — the media packages moved to mpx (github.com/itsezlife/mpx), consumed by git dependencies pinned to one commit: `catalog_assets`' core, `image_decoder` and `frame_texture` are `mpx_core`; `lottie_native` + `lottie_decoder` are `mpx_lottie`; `video_native` + `video_decoder` are `mpx_video_decoder`. What stayed in the chat is two packages: `glyph_atlas` (over `mpx_core`) and `content_assets` (content by `ContentKey` over `mpx_core`'s cache: the glyph route, embeds, chat presets, the `ContentKey` / `MediaKey` mapping). Rule 8 is retired here: native code and its rules are mpx's (mpx ADR 0001). Rows changed below  
**Relates to**: [ADR 006](006-panel-catalog-viewport.md) (package list in its Decided table is replaced by this one), [ADR 007](007-keyboard-panel-controller.md), [ADR 012](012-cross-platform-selection-policies.md)

## Decided

| Package | Role | Depends on |
| ------- | ---- | ---------- |
| `content_model` | Pure-Dart leaf (its only non-SDK dependencies are `meta` and `listen`, which are not workspace packages). Content identity, collections, data seams (`CollectionSource`, `SearchSource`, `RecentsStore`, `PreferenceStore`, `KeywordSource`, `GlyphSupport`, `KeyValueStore`, `ContentResolver`, `RichClipboard`, `PackSource`, `ContentLibrary`, `LibraryStorage`), reference stores, fakes and contract suites, the inline content ref and the rich-text value, opt-in `markdown.dart` | none |
| `chrome_foundation` | Leaf. Palette, token groups, theme scope, motion roles, strings scope, icon registry, glass. Nothing chat-specific | none |
| `glyph_atlas` | The baked glyph atlas: plan, bake, pages, residency, disk cache, the glyph sources | `mpx_core` (git) |
| `content_assets` | Content by `ContentKey` over `mpx_core`'s asset cache: `ContentAssetScope` (media to the cache, glyphs to the atlas), `ContentAssetView`, inline embeds, chat presets, the `ContentKey` / `MediaKey` mapping and `ContentMediaResolver` | `content_model`, `glyph_atlas`, `mpx_core` (git) |
| `viewport_scroll` | Leaf. A viewport's user-driven scroll: the scroll physics (fling and edge effect, a preset per platform family), their runtime for a viewport that runs them (`engine.dart`), the keyboard scroll keys, and the fast scrollbar (a thumb over any scrollable's controller, a host-labelled section bubble, the host's colours). Nothing chat or panel specific | none (`flutter` only) |
| `panel_catalog` | Catalog viewport. Public seams per [ADR 024](024-panel-catalog-seams.md) | `content_model`, `content_assets`, `mpx_core` (git), `viewport_scroll` |
| `emoji_data` | Emoji-specific logic only: structure and keyword loaders, emoji `CollectionSource`, merged search, variants, pure-Dart glyph probe. No assets, no native code | `content_model` |
| `emoji_catalog_pack` | Catalog structure and per-locale keyword pack assets, plus the pinned generator under `tool/` | `content_model` |
| `kv_shared_preferences` | `shared_preferences`-backed `KeyValueStore` adapter | `content_model` |
| `chat_wallpaper` | Leaf. The chat wallpaper: value model and codec, freeform renderer and keyframes, motion, view, warm-up, service fills ([ADR 040](040-chat-wallpaper.md)). Pattern artwork is the host's | none (`flutter`, `vector_graphics`) |
| `rich_clipboard` | `RichClipboard` adapter: the HTML codec and the platform clipboard code, the workspace's one Flutter plugin package ([ADR 032](032-rich-clipboard.md)) | `content_model` |
| `swipe_pager` | Leaf. A horizontal pager whose swipe is claimed past a slop and a direction rule so page scrollables keep their drags; controller, settle physics, keep-alive policy, right-to-left, semantics and keyboard paging. Nothing panel-specific | none (`flutter` only) |
| `panel_shell` | Host-independent panel: page registry, shell controller, pager, type tabs, bottom bar, search field, panel events, page scroll activity, focus and shortcuts | `chrome_foundation`, `content_model`, `swipe_pager` |
| `panel_pages` | Catalog page scaffold and per-kind policies (emoji, sticker and GIF pages), the content preview and the pack sheets ([ADR 044](044-content-library-packs-and-preview.md)) | `panel_shell`, `panel_catalog`, `content_assets`, `glyph_atlas`, `mpx_core` (git), `content_model`, `chrome_foundation` |
| `panel_presentation` | Sealed presentation kinds, the `$Mobile` / `$Desktop` policy, the presentation controller, occupancy, IME arbitration | `panel_shell`, `chrome_foundation` |
| `composer_editable` | Leaf. The composer's one editable: a renamed, patched copy of the Flutter framework's text field, editable text and selection overlay, with the touch gesture matrix, handle and magnifier motion and the toolbar fade ([ADR 038](038-composer-editable-fork.md)). Nothing chat-specific | none (`flutter` and `characters` only) |
| `chat_composer` | Slot-based composer, input-only controller, entity-aware text controller with formatting commands, selection menu, input query; renders through `composer_editable` | `chrome_foundation`, `content_model`, `content_assets`, `composer_editable` |
| `bulletins` | Bulletins: the bulletin value, the per-surface controller with commit on leave, the host mount with the bottom obstruction seam, the per-platform presentation policy and the stock builders ([ADR 045](045-bulletins.md)). Nothing chat, panel or content specific | `chrome_foundation` |
| `golden_baseline` | Leaf, test support only. `useGoldenBaselines` and the comparator that holds golden baselines to the CI runner | none (`flutter`, `flutter_test`) |
| `chat_scroll_view` (repo root) | The anchor viewport and its markdown bodies: message and text selection, inline hits, the embed adapter, spoiler wiring, `ChatEmojiBody`. Consumes the markdown engine fork by git ref ([ADR 035](035-markdown-engine-fork.md)), which is not a workspace package | `content_assets`, `content_model`, `mpx_core` (git), `viewport_scroll` |

Decoders, the bytes cache and its fetch adapter are mpx's (`mpx_core`'s
image codecs, `mpx_lottie`, `mpx_video_decoder`, `http_bytes_cache`, `mpx`);
the host wires them. Every mpx dependency is a git dependency pinned to the
same full commit sha in every pubspec, moved together.

Rules, enforced by the dependency lint in `scripts/check` ([ADR 030](030-testing-policy.md)):

1. The graph is a DAG. `content_model`, `chrome_foundation` and `composer_editable` depend on no workspace package.
2. No package re-exports another package's API. A host imports what it uses.
3. `panel_shell`, `panel_pages` and `panel_presentation` never depend on data payloads (`emoji_catalog_pack`), codecs or fetchers.
4. Fakes are exported only from a package's `testing.dart` and never used by production code.
5. `panel_catalog` does not depend on `chrome_foundation`. Pages adapt tokens.
6. `composer_editable` is a leaf with `chat_composer` as its only dependent. A host reaches the field through the composer view, never the raw editable.
7. `golden_baseline` is test support: any member may declare it, under `dev_dependencies:` only, and a leaf that does stays a leaf. No library ships it.
8. Retired with the move to mpx (native code and its rules are mpx's). `panel_shell`, `panel_pages` and `panel_presentation` still depend on no decoder; only the host wires a decoder into a `DecoderRegistry`. `content_model` takes no mpx dependency.

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

## Amendment (2026-11-26, accepted): `message_media` and `chat_capabilities`

Two packages join the graph ([ADR 047](047-message-media.md),
[ADR 049](049-chat-capabilities.md)); a third, `chat_outbox`, comes with
[ADR 048](048-outgoing-messages.md) (Accepted 2026-11-26, maintainer;
acceptance-2) and its row below is accepted with it. Held by convention: the dependency lint is not extended
for them.

| Package | Role | Depends on |
| ------- | ---- | ---------- |
| `chat_capabilities` | Leaf. Chat capabilities: the per-chat value of outcomes and denial reasons, its groups (sending, write access, slow mode, protection, limits), the bit-flag sets, the denial feedback hooks; fakes in `testing.dart`. Nothing about a backend's protocol | none (`meta` and `listen` only) |
| `chat_outbox` (ADR 048) | The outbox: outgoing messages over mpx publish jobs, their status, the provisional tail's id strategies (`allocate` / `rebase`, sequential server ids and local ids), the `chat.send` publisher over the host's sender, cancel, retry, the restart query, the send origin hand-off; fakes in `testing.dart`. No store of its own | `mpx_transfer` (git), `mpx_core` (git), `attach_model`, `content_model`, `chat_capabilities`, `chat_scroll_view` (root, for `rebaseTail`) |
| `message_media` | Message media display: the message media policy, media layouts and their interpolation, cells and chrome slots, the file stack, the link preview card, the optional bubble layout helper, the per-chat media state, item semantics. No transfers, no outbox, no saving | `content_model`, `content_assets`, `chat_capabilities`, `chrome_foundation`, `mpx_core` (git), `chat_scroll_view` (root) |

Edges into the new leaf: `chat_composer` (message length and the input row
panel from the capabilities), `attach_sheet` (it builds `AttachLimits` from
the capabilities itself) and, with ADR 048, `chat_outbox`. `attach_model`
takes no edge: [ADR 046](046-media-picker.md) rule 1 stands (`attach_model`
depends on `content_model` only). The root `chat_scroll_view` (its
`canCopy(messageId)` selection hook) and `panel_shell` (page availability)
take none either: the host sets both from the capabilities.

Rules added:

9. `chat_capabilities` is a leaf: it depends on no workspace package and
   imports no Flutter.
10. `message_media` never depends on `mpx_transfer` (a display-only host must
    not inherit a transfer plugin) or on `chat_composer`; `chat_composer`
    never depends on `message_media`.

11. `message_media` may depend on the root `chat_scroll_view` package, the
    first workspace package to do so: message media is a chat body and
    registers with the viewport's non-text body seam and inline hits. A host
    without a chat shows media through mpx's `AssetView` or `mpx_ui`. The
    root never depends on `message_media`, so the graph stays a DAG.
12. (Accepted with ADR 048.) `chat_outbox` may depend on the root
    `chat_scroll_view` package (for `rebaseTail`) and on `mpx_core`, as
    rule 11 allows for `message_media`. `message_media` never depends on
    `chat_outbox` (rule 10 would be broken through it), and the root
    `chat_scroll_view` never depends on it: the engine gains only
    `rebaseTail` and knows no outbox. No cycle.

`content_model` gains the media item values (`MediaItem`, `MediaItemId`,
`MediaItemKind`), so the outbox and the picker name items without
`message_media`; no edge changes for it. `message_media` takes
`content_assets` because its cells draw through `ContentAssetView`.
