# ADR 029: Host integration and wiring

There is no facade package and no service locator. Every package exposes plain
constructors and a scope widget. The host builds one composition root that
creates long-lived services in dependency order, and each package README
carries a Host contract table. Message bodies paint inline content through a
generic painter-based embed seam.

**Status**: Accepted  
**Date**: 2026-10-16  
**Amended**: 2026-10-18 — the scope boundary is lifted: inline embeds are implemented in the markdown fork and the root viewport; size rule `1.2 × (ascent + descent)`; alt text atomic for selection; `ChatInlineHit.embed`; unresolved targets paint their alt text (rows changed below: Message bodies, Scope boundary; triggers: [ADR 035](035-markdown-engine-fork.md), [ADR 037](037-spoiler-and-mention-inline-styles.md))  
**Relates to**: [ADR 013](013-viewport-owns-markdown-text-selection.md), [ADR 017](017-body-linkify-host-invoked.md), [ADR 020](020-package-topology.md), [ADR 022](022-asset-cache-and-media-pipeline.md), [ADR 025](025-panel-shell-and-pages.md), [ADR 028](028-panel-presentation.md), [ADR 035](035-markdown-engine-fork.md), [ADR 037](037-spoiler-and-mention-inline-styles.md)

## Decided

| Area | Decision |
| ---- | -------- |
| Composition | Each package exposes plain constructors and a scope widget (`ChromeThemeScope`, `ChromeStringsScope`, `AssetCacheProvider` around a host-created `AssetCacheScope`, ...). The host builds one composition root creating long-lived services in dependency order: `KeyValueStore` adapter, stores (async factories that arrive loaded), asset cache (fetcher, decoders, spec and profile presets, budgets), data sources (collection, search, recents, keyword), content resolver. Per-chat controllers are created per chat screen. The reference host is the demo app under `example/`. Each package README has a Host contract table: what the host provides and what it must not do. |
| Message bodies | A generic painter-based **inline embed** seam in the markdown library and root viewport. The markdown library owns the contract and has no asset dependency: `MarkdownInlineEmbedResolver` maps an embed target (scheme, id, alt) and the paragraph's text metrics (font size, ascent, descent, device pixel ratio) to a `MarkdownInlineEmbed` with a size, a `paint(canvas, rect, context)` callback, a `visible` switch and an invalidation listener. The root package ships one adapter over `catalog_assets`' `InlineEmbedResolver`, and `catalog_assets` ships `ContentEmbed` (attaches a key with a preset, paints the `AssetPaintable`, detaches on dispose) and `ContentEmbedResolver` (reads targets spelled as `ContentKey.encoded`). The host registers a resolver per scheme on the body widget; the painter owns every embed it resolved and disposes them with the model. The host converts between the rich-text value and markdown (`![alt](unicode:1F44D)` is the `ContentKey.encoded` spelling; `RichTextMarkdown` in `content_model` is that helper). Bodies stay markdown ([ADR 017](017-body-linkify-host-invoked.md)); there are no parallel entity offsets. |
| Embed layout | One fork-owned placeholder per embed in the paragraph, aligned to the middle of the line, so layout and baseline come from the text engine. The placeholder is one code unit while the alt text may be several, so selection mixins keep an offset map between painter text and rendered text. Size: a square of `1.2 × (ascent + descent)` of the paragraph font, rounded to device pixels, computed once per paragraph style so every embed of a paragraph shares one `AssetSpec` and one cache entry per key; centred on the line, line height untouched (the overflow is not clipped). A bare emoji character in a body is a glyph, never an embed; the `unicode:` spelling is legal and resolves through the same resolver, but no host must emit it. |
| Embed paint | A live pass after the glyph picture and after every selection highlight, the last pass; the glyph picture is never re-recorded for an embed frame. Embed signals coalesce into one repaint per render object. `visible` follows whether the block intersects the painted viewport; global pause layers stay the asset cache's ([ADR 022](022-asset-cache-and-media-pipeline.md)). No selection tint is ever painted over an embed (amended: the highlight is one rectangle per line behind glyphs, emoji and embeds, as Telegram's, so a selected embed reads as selected by the highlight round it and nothing about a hidden spoiler's emoji leaks; the fork's `docs/rendering.md` *Selection highlight* lists the reference rules and divergences). |
| Embed text and hits | The alt text is the rendered text of the embed and is atomic for selection: a boundary inside an embed snaps outward to cover it. Copy yields the alt; semantics stay paragraph-level, with no node per embed. A tap is `ChatInlineHit.embed` (message id, target, alt, contour, touch origin); image spans are no longer reported as links, and the host decides what an embed tap means. An unresolved target (no resolver for the scheme, or a resolver that returns nothing) paints its alt text in the surrounding style: no broken mark, no box ([ADR 022](022-asset-cache-and-media-pipeline.md), no visible failed stage). |
| Scope boundary | The root `chat_scroll_view` package depends on `catalog_assets` and `content_model` (the embed adapter and the emoji-only body's input, [ADR 036](036-emoji-only-message-presentation.md)); the markdown library stays free of both. The earlier "no asset dependency" was always about the library. |

### Ownership and lifetime

| Object | Created by | Lifetime | Disposed by |
| ------ | ---------- | -------- | ----------- |
| `KeyValueStore` adapter, stores, content resolver, fetcher, decoder registration | Host | App or account | Host |
| Asset cache (`AssetCacheScope`; widgets read it through `AssetCacheProvider`) | Host | App-wide | Host |
| Pause layers, connectivity-restored signal | Host, fed into the cache | App | Host |
| Emoji data sources (payload, keyword source); sticker and GIF sources | Host | Account | Host |
| `ChromeThemeScope`, `GlassQuality`, speed scale | Host | App, plus per-chat nested scope | Host |
| `GlassSourceScope` | Chat screen, over chat content | Chat screen | Chat screen |
| `ComposerController`, `PanelShellController`, `PanelPresentationController`, per-page controllers | Chat screen | Chat screen | Chat screen |
| `ComposerSpec`, panel page list | Host, rebuilt from chat state, permissions and draft | Chat screen | Host |
| `bottomPadding` aggregation; `PanelEvent` handler (insert, `RecentsStore.record`) | Host | Chat screen | Host |
| Inline embed resolvers | Host, registered per scheme | Body setup | Host |

The creator disposes. A scope never disposes what it was handed; a scope that
constructs something says so.

A minimal host for an emoji-only keyboard uses `chrome_foundation`,
`content_model`, `catalog_assets`, `emoji_data` with `emoji_catalog_pack`, a
KV adapter, `panel_catalog`, `panel_shell`, `panel_pages`, `panel_presentation`
and `chat_composer`. Sticker and GIF pages add host-implemented sources;
animated media adds fetcher and decoder adapters.

## Why

- Wiring the old chrome meant constructing seven objects by hand, six dispose calls, a duplicated data-source creation and panel state in four places.
- The host owns aggregation of occluding chrome into the viewport ([host insets](../architecture/14-host-chrome-insets.md)), and package APIs name roles rather than screens ([portable surface](../agents/portable-surface.md)).
- Bodies are markdown and the viewport owns text selection ([ADR 013](013-viewport-owns-markdown-text-selection.md)), so embeds must go through body layout, not widgets or parallel offsets.

## Rejected

| Alternative | Why not |
| ----------- | ------- |
| A kit or builder package; a global service locator | The umbrella topology was rejected ([ADR 020](020-package-topology.md)); hidden dependencies |
| `WidgetSpan` embeds; `ImageProvider`-based embeds | They bypass budgets, the shared clock, pause layers and vector or animated paintables |
| An embed contract owned by `catalog_assets` and implemented by the markdown library; a micro-package for the contract | It ties the cache to one renderer; three abstract classes do not earn a package |
| Painting the alt glyphs transparent and drawing over their box | The size is uncontrollable and breaks the size rule |

## Related

- Host contract tables: each package README
- Walkthrough of the composition order and the reference host: [Host integration guide](../host-integration.md)
