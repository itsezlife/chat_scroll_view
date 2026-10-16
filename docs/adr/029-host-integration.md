# ADR 029: Host integration and wiring

There is no facade package and no service locator. Every package exposes plain
constructors and a scope widget. The host builds one composition root that
creates long-lived services in dependency order, and each package README
carries a Host contract table. Message bodies paint inline content through a
generic painter-based embed seam.

**Status**: Accepted  
**Date**: 2026-10-16  
**Relates to**: [ADR 013](013-viewport-owns-markdown-text-selection.md), [ADR 017](017-body-linkify-host-invoked.md), [ADR 020](020-package-topology.md), [ADR 022](022-asset-cache-and-media-pipeline.md), [ADR 025](025-panel-shell-and-pages.md), [ADR 028](028-panel-presentation.md)

## Decided

| Area | Decision |
| ---- | -------- |
| Composition | Each package exposes plain constructors and a scope widget (`ChromeThemeScope`, `ChromeStringsScope`, `AssetCacheProvider` around a host-created `AssetCacheScope`, ...). The host builds one composition root creating long-lived services in dependency order: `KeyValueStore` adapter, stores (async factories that arrive loaded), asset cache (fetcher, decoders, spec and profile presets, budgets), data sources (collection, search, recents, keyword), content resolver. Per-chat controllers are created per chat screen. The reference host is the demo app under `example/`. Each package README has a Host contract table: what the host provides and what it must not do. |
| Message bodies | A generic painter-based **inline embed** seam in the markdown library and root viewport, with no asset dependency. `InlineEmbedResolver.resolve(target, metrics)` maps a link or image target (scheme, id, alt) and the text metrics (font size, density) to an `InlineEmbed` with a size hint, a `paint(canvas, rect, context)` callback and an invalidation listener. The alt text is the copy, selection and accessibility text. `catalog_assets` ships `ContentEmbed`, which attaches a key with the inline-message preset, paints the `AssetPaintable` and detaches on dispose, and `ContentEmbedResolver`, which reads targets spelled as `ContentKey.encoded`. The host converts between the rich-text value and markdown (for example `![alt](unicode:1F44D)`, the `ContentKey.encoded` spelling; `RichTextMarkdown` in `content_model` is that helper) with a documented, tested helper. Bodies stay markdown ([ADR 017](017-body-linkify-host-invoked.md)); there are no parallel entity offsets. |
| Scope boundary | Implementing the embed seam in the markdown fork and the root viewport is outside this decision and tracked as follow-up work. The contract and `ContentEmbed` ship ready for it. |

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
| Designing the markdown and viewport implementation inside the package effort; making it dependent work | It is separate engine work with its own risks |

## Related

- Host contract tables: each package README
- Walkthrough of the composition order and the reference host: [Host integration guide](../host-integration.md)
