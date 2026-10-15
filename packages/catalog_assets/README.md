# catalog_assets

Process-wide global catalog asset cache for catalog and conversation leaves.

## Contract

- Bind by key + cache-type / size class
- Observe leaf readiness: `loading` / `ready` / `failed` (`readinessOf`)
- Attach / detach: `isRetained` while a surface is bound; ready/failed entries
  survive the last detach (pager leave/return); loading-only orphans drop
- Fetch/decode stays outside this package; `MemoryCatalogAssetCache` /
  `FakeCatalogAssetCache` drive readiness for hosts and deterministic tests
- Explicit `evict` / `clear` for memory pressure (no LRU yet)

No scroll-viewport RenderObject dependency.

## Glyph atlas (`glyph_atlas.dart`, `testing.dart`)

Bakes the glyphs a host supplies into fixed-size **glyph atlas pages** and
answers where each **baked glyph** (sprite: page plus source rectangle) is.
Independent of the cache above; the cache and the viewport consume it later.
Terms: [Panel Catalog glossary](../../docs/panel-catalog/CONTEXT.md)
(Glyph atlas page, Bake, Baked glyph).

| Piece | Role |
| --- | --- |
| `GlyphAtlasLayout` | Page 2048 px, glyph capped at 72 px, 2 px gutter: 676 cells per page; the three constants are the only knobs |
| `GlyphAtlasIndex` | Fixed plan: which page and cell each glyph is baked into (pure data) |
| `GlyphBaker` | Strips of a few glyphs, then one page composed per step; the caller paces the steps |
| `GlyphRasteriser` (seam) | Paints one glyph; `ParagraphGlyphRasteriser` uses the system font |
| `GlyphPageStore` (seam) | Keeps composed pages; the in-memory fake is in `testing.dart` |

Host contract:

| The host provides | The host must not |
| --- | --- |
| The glyph list (the data layer decides which glyphs exist) | Ask the baker to detect missing glyphs or fall back to a paragraph |
| Pacing: when to call `step`, and how many glyphs per frame | Call `step` from a spawned isolate (text and picture APIs are root-isolate only) |
| A `GlyphPageStore` | Mutate or share a stored page; handles are cloned on write and read |

`testing.dart` ships `FakeGlyphRasteriser` (predictable pixels, no emoji font),
`FakeGlyphPageStore`, `ImagePixels`, and the contract suites
`runGlyphRasteriserContract` and `runGlyphPageStoreContract` for adapter authors.
On-device check: `example/integration_test/glyph_atlas_bake_test.dart`.
