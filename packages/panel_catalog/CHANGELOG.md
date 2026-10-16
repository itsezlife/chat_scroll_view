# Changelog

All notable changes to `panel_catalog` are documented in this file. The format
is loosely based on [Keep a Changelog](https://keepachangelog.com/); this package
is pre-1.0.

## [Unreleased]

### Changed

- **BREAKING: leaf value and hit.** `CatalogLeaf` is a value (content key,
  descriptor paint facts, opaque host `tag` excluded from equality) instead of
  the sealed `UnicodeCatalogLeaf` / `DocumentCatalogLeaf` pair, and
  `CatalogLeafPresentation` is deleted: the placeholder style is derived from
  the leaf's facts (`CatalogLeaf.placeholderStyle`). `onLeafTap`, the
  long-press callbacks and `leafLongPressEligible` take a
  `CatalogLeafHit(sectionId, index, leaf)`; hit identity is the cell, so the
  same key in two sections is two hits. A host keeps its per-cell metadata in
  the leaf's `tag` instead of a map keyed by leaf instance.
- **BREAKING: per-section layout.** `CatalogSection` takes an optional
  `SectionLayout` (`SectionLayout.grid`); the viewport's `spanCount`,
  `cellExtent` and `headerExtent` become defaults. Section landing, the near /
  far gate and slot projection use each section's own geometry;
  `scrollOffsetForSectionHeader` takes the `maxWidth` it is laid out at.
  The stitch matches outgoing cells by (section, index) instead of by content
  key.
- **BREAKING: snapshot data source.** `CatalogDataSource` and its listener list
  are replaced by an immutable `CatalogSnapshot` published through a
  `ValueObservable<CatalogSnapshot>` (`content_model`); `PanelCatalogViewport`
  takes `snapshots` instead of `dataSource`. `FakeCatalogDataSource` becomes
  `FakeCatalogSnapshotSource` in the new `package:panel_catalog/testing.dart`.
- **BREAKING: attach-and-position controller.** The render object attaches one
  `CatalogScrollPosition` to `PanelCatalogController`; the five listener
  channels (`addScrollListener`, `addJumpListener`, `addScrollByListener`,
  `addAnimateToListener`, `addSectionJumpListener`) and the viewport-only
  write methods are deleted. `controller.events` is the one typed Observable.
  Commands given with no viewport commit a target that the next viewport starts
  from; a `jumpToSection` given before the first layout is applied after it.
- **The bake pause is event-driven.** `CatalogBakeActivity` derives its two
  outputs from the controller's events instead of the paint offset and
  publishes them as `PanelCatalogScrollingChanged` and
  `PanelCatalogScrollSettled(visibleKeys)`. The interim forwarding to the
  cache's glyph atlas is `CatalogAtlasBakeBridge`, deleted with the legacy
  cache API.

### Added

- `SectionLayout`, `CatalogLeafHit`, `CatalogPlaceholderStyle`,
  `catalogGlyphBoxExtent` and `largestCatalogGlyphBox`: the rule that sizes a
  single baked glyph size for sections with different cell sizes.
- `PanelCatalogUserDragCancel`, `PanelCatalogScrollingChanged`,
  `PanelCatalogScrollSettled` scroll events; `PanelCatalogController` extents
  (`viewportExtent`, `contentExtent`, `maxScrollExtent`, `hasPosition`).

- **Baked sprites on screen.** When the asset cache has a
  `CatalogAssetCache.glyphAtlas`, unicode leaves are drawn as sprites cut from
  its pages: the painter queues each sprite and one paint pass draws every
  page's sprites with a single batched atlas draw (the pressed cell is scaled
  inside its batch). Existing behaviour is the web strategy: with no atlas
  glyphs are drawn as paragraphs, as before.
- **`panel_catalog_diagnostics.dart`** — `PanelCatalogDiagnostics.glyphParagraphDraws`,
  the proof that no emoji is drawn as text where emoji are baked (`0`). Bumped
  only on the paragraph path, so the sprite path pays nothing.
- **Bake stays out of the way.** The viewport tells the atlas when it scrolls
  (drag, fling, jump, wheel, section motion) and, once it settles, which glyphs
  are on screen so their page bakes first.

- **`kCatalogGlyphBoxFraction`** (0.72) — the share of a cell's shorter side a
  glyph is drawn in, public so a host that bakes glyphs sizes them for it.

### Changed

- **The viewport is a repaint boundary.** `RenderPanelCatalog.isRepaintBoundary`
  is `true`: paint runs into a layer of its own, so a host that stacked
  viewports sees one more compositing layer per viewport. Scrolling repaints
  that layer without repainting what is around it, and what is around it does
  not repaint the viewport.

### Removed

- **Cold-start warm-up.** `PanelCatalogController.warmAhead`, the render
  object's band walk, `CatalogLeafPainter.rasterizeGlyphsForWarmup` /
  `ensureGlyphParagraph` / `cancelWarmup`, the viewport's device-pixel-ratio
  field that only fed it, and the `PANEL_PERF_SKIP_WARM` switch are gone. The
  offscreen `toImage` pass did not make the first fling cheaper, and where emoji
  are baked it built paragraphs that are never drawn. A host that called
  `warmAhead` drops the call; nothing replaces it (the atlas bakes in the
  background). On platforms that bake, no emoji paragraph is built at all.
- **Experiment switches.** The `panel_catalog_perf_probe.dart` library (a
  glyph override and paint coverage statistics read by the paint path) is
  deleted with its two engine call sites. It was never exported; hosts and
  tests measure through `PanelCatalogController` and the viewport's public
  geometry, and `PanelCatalogDiagnostics` stays as the one observation entry.

### Changed

- **Bounded paragraph caches.** On the paragraph path (the web strategy) the
  glyph cache keeps at most 1024 paragraphs per viewport
  (`kGlyphParagraphCacheLimit`) and the section-header cache 64, least recently
  drawn out first. A paragraph that leaves a cache, by eviction or when the
  viewport is disposed, is disposed. Before, a window resized step by step
  added a screenful of paragraphs per step for the life of the viewport.
- **Unicode presentation with an atlas.** An unbaked glyph is
  `CatalogLeafPresentation.circlePlaceholder` (never text) and flips to
  `content` when its page lands, without a layout change. Hosts that pass a
  cache without an atlas see no difference.

### Changed

- **Diagnostics logger.** `PanelCatalogDevLog`, `DevLogFormat` and
  `kPanelCatalogDevLog` are removed from the public API. Diagnostics go through
  an internal logger by category (`layout`, `binding`, `scroll`, `paint`),
  off by default. Enable one with
  `--dart-define=panel_catalog.debug.<category>=true` or a
  `#panel_catalog.debug.<category>: true` zone value, or all of them with
  `panel_catalog.debug`. Console name is `panel_catalog.<category>`.

### Changed

- **Unicode presentation** — unbound/loading [UnicodeCatalogLeaf] resolves to
  [CatalogLeafPresentation.content] (paragraph paint; no decode wait). Avoids
  circle-placeholder flash after pager keep-alive detach / empty sync.
  [CatalogLeafPresentation.circlePlaceholder] reserved for a future
  bitmap-page path. Failed unicode still uses [CatalogLeafPresentation.failed].
- **Settled cache readiness across detach** — [presentationFor] falls back to
  [CatalogAssetCache.readinessOf] when unbound so ready document leaves stay
  [CatalogLeafPresentation.content] after pool [detachAll] (pager reattach).
- **Far-path distance gate** — near path when flat-row distance `≤ 9`
  ([kFarPathDistanceGateFactor]), not `spanCount × 9` rows. Equivalent to
  `spanCount × 9` in per-cell adapter space. The previous multiplier
  over-widened near-path smooth scroll.
- **`PanelCatalogController.jumpToSection` re-entry** — while
  [isSectionJumpActive], additional requests are ignored and return the
  in-flight future; user drag still cancels.
- **`PanelCatalogViewport.placeholderColor` removed** — use
  [PanelCatalogThemeData.placeholderColor] via [PanelCatalogTheme] instead.

### Added

- **`PanelCatalogTheme`** + **`PanelCatalogThemeData`** — inherited theme for
  all catalog paint tokens (placeholder, press highlight, section header,
  stand-in corner radius, document stub fill). [PanelCatalogThemeData.lerp]
  for transitions.
- Painted **list-selector highlight** on pressed leaf cells (full cell rect,
  opacity ∝ press progress) alongside existing glyph scale.
- **`PanelCatalogThemeData`** extended with `sectionHeaderColor`,
  `documentStandInColor`, `standInCornerRadius` — all catalog paint colors
  now resolve from inherited theme (no hardcoded painter literals).
- **`PanelCatalogController.jumpToSection`** — programmatic section landing
  under viewport top inset with near-path smooth scroll when the far-path
  distance gate passes (`≤ 9` flat rows, [kFarPathDistanceGateFactor]) and
  far-path [CatalogFarStitch] (capture → teleport → dual-translate) when the
  gate fails. Exposes [isSectionJumpActive] for host strip-sync gating during
  programmatic motion.
- **`leafLongPressEligible`** on [PanelCatalogViewport] — per-leaf gate for
  registering the long-press recognizer. Ineligible leaves stay tap-only so
  plain glyphs do not lose tap after the long-press timeout.

## [0.1.0] - 2026-08-25

### Added

- **`PanelCatalogViewport`** — extent-scroll catalog body as a
  `LeafRenderObjectWidget` with package-private `RenderPanelCatalog` engine.
- **Paint leaves** — section headers and grid cells drawn on a clipped canvas;
  visible-band asset bind/recycle via `CatalogLeafBindingPool` (no per-cell
  widget default).
- **`PanelCatalogController`** — absolute content offset with typed jump /
  scroll-by listeners and silent viewport clamp via `correctOffset`.
- **`CatalogDataSource`** contract plus `FakeCatalogDataSource` for tests.
- **Leaf / section models** — `CatalogLeaf` (unicode + document identity),
  `CatalogSection`, `CatalogLeafPresentation` (circle / thumb-first / shaped
  wash / content / failed).
- **Viewport-owned hit-test** — `leafAt` maps pointers to `CatalogLeaf`;
  shell callbacks `onLeafTap` and long-press start/move/end with leaf identity.
- **Press scale in paint** — `0.8 + 0.2 * (1 − progress)` via
  `CatalogLeafPress`; test seams `pressedSlotKey` / `pressProgress` on the render
  object.
- **Ballistic fling** — `CatalogScrollPhysics` (`ClampingScrollSimulation`) on
  drag-end; pointer-down while flinging cancels coast and suppresses leaf
  tap/long-press for that pointer (no accidental insert while stopping scroll).
- **Widget tests** — fake data source + stub asset cache at the public viewport
  API (scroll, notify, placeholders, hit-test, fling cancel).

### Dependencies

- `catalog_assets` for process-wide asset readiness and attach/refcount.
