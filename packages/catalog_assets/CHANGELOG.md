# Changelog

All notable changes to `catalog_assets` are documented in this file. The format
is loosely based on [Keep a Changelog](https://keepachangelog.com/); this package
is pre-1.0.

## [Unreleased]

### Added

- **Glyph atlas** (`glyph_atlas.dart`) — `GlyphAtlasLayout` (2048 px pages, glyph
  capped at 72 px, 2 px gutter), `GlyphAtlasIndex` / `GlyphSprite`, the paced
  `GlyphBaker`, and the `GlyphRasteriser` / `GlyphPageStore` seams with
  `ParagraphGlyphRasteriser`. Independent of the asset cache.
- **`testing.dart`** — `FakeGlyphRasteriser`, `FakeGlyphPageStore`,
  `ImagePixels` and the `runGlyphRasteriserContract` /
  `runGlyphPageStoreContract` suites.

- **Paced baking** — `GlyphBakeScheduler` drives the baker one step per frame
  from an injected `BakeFrameSource` and clock; `BakeGovernor` adapts glyphs
  per frame (up to 16) to measured frame cost; `BakePauseSignals` pause it for
  a hidden panel, scrolling and the open animation. `GlyphBaker.prioritise`
  bakes the pages holding the visible glyphs first. Fakes and
  `runBakeFrameSourceContract` ship in `testing.dart`.

### Changed

- `GlyphBaker` no longer bakes strictly in page order once `prioritise` is
  called; without it the order is unchanged. A page in progress that holds none
  of the prioritised glyphs is dropped and bakes again later.
- The package now depends on the Flutter SDK (`dart:ui` for the baker) and on
  `flutter_test` (contract suites); its tests run with `flutter test`.

### Changed

- **Ready/failed retention** — after the last [CatalogAssetBinding.detach],
  settled entries stay in [MemoryCatalogAssetCache] so re-attach keeps
  readiness (pager keep-alive leave/return). Loading-only orphans are still
  dropped. [CatalogAssetCache.readinessOf] is on the interface;
  [MemoryCatalogAssetCache.evict] / [clear] for explicit drop.

## [0.1.0] - 2026-08-25

### Added

- **`CatalogAssetCache`** — process-wide attach/refcount contract for catalog and
  conversation leaves (key + cache-type / size class + readiness).
- **`CatalogAssetKey`** — sealed unicode / document identity for cache lookup.
- **`CatalogAssetCacheType`** — size-class attach hint (e.g. keyboard vs inline).
- **`CatalogAssetReadiness`** — `loading` / `ready` / `failed` observation.
- **`CatalogAssetBinding`** — surface bind handle with readiness listener.
- **`MemoryCatalogAssetCache`** — in-memory implementation for hosts and tests.
- **`FakeCatalogAssetCache`** — deterministic readiness for widget tests.
- **Unit tests** at the public cache API.

### Non-goals

- No RenderObject dependency; fetch/decode orchestration stays in hosts.
