# ADR 023: Data layering, catalog shipping and persistence

Catalog data comes from small seams in `content_model` that pages compose.
The emoji catalog is generated from pinned Unicode and CLDR inputs and ships as
one structure asset plus one keyword pack per locale. Persistence goes through
one `KeyValueStore` seam. Change notification is one synchronous `Observable`.

**Status**: Accepted  
**Date**: 2026-10-16  
**Relates to**: [ADR 020](020-package-topology.md), [ADR 021](021-content-identity-and-collections.md), [ADR 022](022-asset-cache-and-media-pipeline.md)

## Decided

| Area | Decision |
| ---- | -------- |
| Sourcing | A pinned, reproducible generator in the repo: Unicode `emoji-test.txt` (structure, order, groups, variants) plus CLDR annotations (keywords and spoken names per locale). Inputs are pinned by version and the Unicode-3.0 licence notices are kept. The copied picker tables and the Dart `const` locale files are deleted. |
| Shipping | One locale-independent **catalog structure** asset and one **keyword pack** asset per locale (JSON or TSV), loaded lazily, about 26 to 41 KB gzip per locale. Assets and generator live in `emoji_catalog_pack`. |
| Keyword seam | `KeywordSource`: bundled packs are the offline baseline; a host may supply server packs (per language, versioned). |
| Seams | In `content_model`: `CollectionSource` (ordered collections, per-collection contents with state and paging), `SearchSource` (query to a paged results collection), `RecentsStore`, `PreferenceStore`, `KeywordSource`, `GlyphSupport`, `KeyValueStore`, `ContentResolver`. No facade interface. Pages compose only what they need (emoji page: all; GIF page: collection, search and recents). |
| Reactivity | One small synchronous pure-Dart `Observable`, with a value-carrying variant: dedup on add, snapshot dispatch, one notification per logical mutation, silent after dispose (the semantics of [ADR 007](007-keyboard-panel-controller.md)'s listener pattern). Flutter adapts it to `ValueListenable` in one place. |
| Glyph support | `GlyphSupport` seam with one cross-platform pure-Dart rasterise-and-compare probe in `emoji_data`. No native directory and no method channel anywhere. The system emoji art version signal that invalidates the probe result and the baked atlas cache key is a pixel fingerprint of a few sentinel glyphs rendered once per launch and compared with the stored value. An operating-system version string is at most a supplementary signal. The signal is produced once and shared by every consumer. The probe is paced like the bake: a few glyphs per frame under a frame-time governor, paused during the panel open animation and scrolling, and sharing the bake's rasterisation pass where one exists. Validation on Android, Windows and Linux is an acceptance criterion; the fallback is a thin Android-only native adapter behind the same seam, supplying glyph support and never the version signal. Without an adapter, everything shows. |
| Persistence | Logic packages depend only on `KeyValueStore`: async get, set and remove, namespaced keys, versioned values. The `shared_preferences` adapter lives in `kv_shared_preferences`; the in-memory fake lives in `content_model`. Async factories return loaded stores, so there is no unloaded state and no silent drop before load. One namespace per package, structured versioned records, no legacy dual-read. |
| Recents | `record(key, {source})` is called by the host when it decides a pick counts (insert or send). Search picks do not record. Any content key can be recorded; entries keep count and last-used time; order is frequency, then recency; default cap 48, configurable; recents are separate per semantic kind. Bare keys resolve through `ContentResolver` for display. |
| Search | The host supplies an ordered language set (default: app locale plus English). One pack per language, merged. Rank: exact, then prefix, then later-token prefix, then recents frequency; de-duplicate by key. Flags and CLDR names are plain keywords. Results are a paged collection. |
| Placement | `content_model`: interfaces, `Observable`, reference implementations over the seams (KV-backed recents and preference stores) and fakes. `emoji_data`: emoji-specific logic only. Server-backed sticker and GIF sources, and any `KeywordSource` fed from a server, are host-implemented. |

## Why

- The old catalog was stale and unstamped: 313 emoji missing, 12 duplicates, about 26% keyword drift. Eleven locales cost 1.8 MB in the binary, and the native plugin worked only on Android. Telegram bundles structure and ships keyword packs per language from the server on all three clients.
- The old code had five hand-rolled listener mechanisms and persistence across three stores and four key families, with silent drops before load.
- Telegram clients record recents at send time and keep both unicode and custom-emoji ids; keyword search is multi-language.
- A pixel fingerprint needs no native call and tracks what matters, the art, which an OS version string does not (it changes without the art changing).

## Rejected

| Alternative | Why not |
| ----------- | ------- |
| All locales as `const` in the binary; published data packages | No server-pack seam; published packages lag the Emoji release and lack multilingual CLDR keywords |
| Per-kind facades; one generic content data source | A monolith again |
| Streams; Flutter `Listenable` in the leaf | Async lag and subscription lifetimes; the leaf stays pure Dart |
| Keeping the Android-only native plugin; a native font-version call; an unpaced probe; dropping filtering; bundling emoji art | Native code in `emoji_data`; a long raster-thread burst; unsupported glyphs would show as boxes; the system look would be lost |
| `shared_preferences` directly in logic packages; per-package files or databases | Couples logic to one plugin and fragments persistence |
| Pure MRU recents; recording inside the page on tap; app-locale-only search | Telegram parity and host control over what counts as a pick |

## Related

- Glossary: [Content and assets](../content/CONTEXT.md)
- Atlas side of the shared bake pass: [ADR 022](022-asset-cache-and-media-pipeline.md), [ADR 006](006-panel-catalog-viewport.md)
