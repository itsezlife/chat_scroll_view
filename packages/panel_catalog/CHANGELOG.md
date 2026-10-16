# Changelog

All notable changes to `panel_catalog` are documented in this file. The format
is loosely based on [Keep a Changelog](https://keepachangelog.com/); this package
is pre-1.0.

## [Unreleased]

### Added

- An adaptive grid: `SectionLayout.grid(desiredCellWidth:, cellHeightInset:)`
  fits as many columns of the desired width as the width allows, widens the
  cell to share the room and centres the remainder ([ADR 024](../../docs/adr/024-panel-catalog-seams.md)
  amendment).

### Changed

- A mouse no longer drags the catalogue; the wheel and the scrollbar scroll
  it.

### Added

- Mouse seams on `PanelCatalogViewport` ([ADR 024](../../docs/adr/024-panel-catalog-seams.md)):
  `onLeafSecondaryTap(hit, globalPosition)` for a mouse's right button (button
  up); `leafLongPressDelay(hit, kind)`, a long-press delay per cell and pointer
  kind (null: the platform's; `Duration.zero`: at once, a click that lifts
  sooner stays a tap); `pinnedLeaf`, which keeps one cell's hover wash and
  ignores the wheel while a host surface is open over it.
- `PanelCatalogController.leafBoundsOf(hit)` and `viewportBounds`: global
  rectangles, through two new members of the `CatalogScrollPosition` contract
  (the fake answers what a test sets).
- Hover highlight: `PanelCatalogThemeData.leafHoverHighlightColor` (null, the
  default, paints none), `leafHoverHighlightRadius` (8) and
  `leafHoverHighlightInset` (2). A mouse over a leaf paints a rounded wash on its
  cell, under the content, instantly; a finger or stylus in contact never
  hovers, and content moving under a still mouse moves the wash with it.

- `PanelCatalogCurrentSectionChanged` on `controller.events`, and
  `controller.currentSection`: which section the viewport is in (the last whose
  header reached the landing line; at the end of scrolling content the last
  one), for a page's category strip. Source-breaking for an exhaustive `switch`
  over `PanelCatalogScrollEvent`, like every event added to the sealed family.
- The headless benchmark runs with semantics off by default (`BENCH_SEMANTICS`
  selects the preset), writes its ratios for the nightly job, and no longer
  asserts a wall-clock ratio for the semantics probe. Nothing a consumer sees.
- **Grid direction.** Cells fill each row start to end: the first leaf of a
  right-to-left grid is at the right edge. `PanelCatalogViewport` follows the
  `Directionality` it sits in; `SectionLayout.grid(textDirection:)` states a
  section's own. Only x changes: rows, extents, landing offsets and the order of
  leaves are the same in both directions, and content is never mirrored. A
  right-to-left header starts its title at the right edge and puts the header
  action at the left.
- **Windowed semantics.** With assistive technology running, the viewport
  describes the leaves of the window it already binds (the visible band and one
  cell of overscan, by binary search) as buttons labelled with
  `CatalogLeaf.semanticLabel` (the spoken name, else the glyph of a unicode
  emoji), plus header, header-action and empty-message nodes; none for the rest
  of the catalogue and none for a skeleton. A leaf node taps through `onLeafTap`,
  long-presses through `onLeafLongPressStart` (start only, where
  `leafLongPressEligible` allows), gives roving focus on `focus` and scrolls its
  cell in on `showOnScreen`; the viewport node scrolls on `scrollUp` and
  `scrollDown`. No node reads a binding or a sprite. `CatalogLeaf.spokenName`
  (carried by `fromDescriptor`) and `CatalogSectionAction.semanticLabel` are new.
- **Roving focus.** `PanelCatalogController.focusedLeaf`, `focusLeaf`,
  `moveFocus(CatalogFocusMove)`, `activateFocusedLeaf` and `clearFocus`, and the
  `PanelCatalogFocusChanged` event. Moves cross rows and sections (empty and
  loading sections are stepped over), keep the screen column vertically across
  sections of other spans and directions, and scroll the cell in under the
  landing inset, with its header when it is in a section's first row. Activating
  reports the same `CatalogLeafHit` a tap does. `CatalogScrollPosition` gains the
  same five members (the fake and the contract suite follow).
- **Focus highlight.** The focused cell paints the press highlight at full alpha
  under its content; `PanelCatalogThemeData.leafFocusHighlightColor` styles it
  separately (null follows the press highlight).
- **Click cursor.** The viewport is a mouse-tracker annotation: the click
  cursor over a leaf the shell can tap or long-press and over a header action it
  listens to.
- **Section states.** `CatalogSection.state` (`CatalogSectionState`: loading,
  failed, loaded) mirrors the collection behind the section. A loading or
  failed section paints `skeletonCount` skeleton leaves (one row of its columns
  by default) after its leaves, in its placeholder style, with no error UI;
  skeletons attach nothing to the asset cache and are not hit targets. A loaded
  section with no leaves paints `emptyMessage` in a row of its own.
- **Header action.** `CatalogSection.action` (`CatalogSectionAction`: id, label
  and / or icon) is painted at the end of the header band; its hit area is the
  whole band tall and at least `kCatalogActionMinHitWidth` wide. A tap reaches
  the new `PanelCatalogViewport.onSectionAction(sectionId, actionId)`.
- **Near-viewport events.** `PanelCatalogSectionNearViewport(sectionId, edge)`
  (`CatalogSectionEdge`: leading, trailing) on `controller.events` when an edge
  of a section comes within `PanelCatalogViewport.sectionNearExtent` of the
  viewport (one viewport height by default), so a page can load a section or
  paginate it. It is no motion and does not touch the scrolling / settled
  facts that pace the bake.

### Changed

- Only the primary button starts the press animation on a cell: a right click
  no longer flashes it. A left click, a touch and a stylus contact are
  unchanged.
- Change notification is `package:listen` (`listen: ^1.0.1`), not
  `content_model`'s removed `Observable` family. **Breaking:** `snapshots` is a
  `ValueListenable<CatalogSnapshot>` (import `package:listen/listen.dart`, not
  Flutter's `ValueListenable`, which is a different type), and
  `controller.events` is a synchronous broadcast `Stream`: `listen` instead of
  `addListener`, cancel the subscription instead of `removeListener`, the same
  callback listened to twice is called twice, and an event a listener
  publishes (the bake activity's `PanelCatalogScrollingChanged`) is delivered
  once the event in flight has reached every listener, still before the
  command that caused it returns. `FakeCatalogSnapshotSource.batch` is gone:
  assign the final snapshot once.
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
  `ValueListenable<CatalogSnapshot>` (`package:listen`); `PanelCatalogViewport`
  takes `snapshots` instead of `dataSource`. `FakeCatalogDataSource` becomes
  `FakeCatalogSnapshotSource` in the new `package:panel_catalog/testing.dart`.
- **BREAKING: attach-and-position controller.** The render object attaches one
  `CatalogScrollPosition` to `PanelCatalogController`; the five listener
  channels (`addScrollListener`, `addJumpListener`, `addScrollByListener`,
  `addAnimateToListener`, `addSectionJumpListener`) and the viewport-only
  write methods are deleted. `controller.events` is the one typed stream.
  Commands given with no viewport commit a target that the next viewport starts
  from; a `jumpToSection` given before the first layout is applied after it.
- **BREAKING: assets come from the host's scope.** `PanelCatalogViewport` takes
  `assets: AssetCacheScope` instead of `assetCache` and `cacheType`; the
  `cacheType` enum is gone and nothing is downcast to a cache implementation.
  Each visible leaf is attached as `attach(key, spec, profile)` (its glyph box
  in physical pixels at the view's density; animate only for an animated leaf,
  and only while in the painted window and not flinging) and the viewport paints
  the binding's `AssetPaintable`: a sprite is queued for the batched atlas draw,
  anything else paints itself. Content that was not there at attach fades in
  over its placeholder; a memory hit does not. There is no `failed`
  presentation: a leaf that fails or hangs keeps its placeholder. A host that
  drew text on the web composes `TextGlyphProducer` into its scope. `CatalogLeaf`
  gains the `tintable` fact (the template decode).
- **BREAKING: slim theme.** `PanelCatalogThemeData` carries the viewport's own
  tokens: `circleColor`, `thumbColor`, `washColor`, `washHighlightColor`,
  `washPeriod`, `skeletonColor`, `placeholderCornerRadius`, press highlight and
  radius, section header style. `placeholderColor`, `documentStandInColor` and
  `standInCornerRadius` (the failed and stub tokens) are gone. The package does
  not depend on `chrome_foundation`.
- **BREAKING: the viewport tells no atlas anything.** `CatalogAtlasBakeBridge`
  is deleted. Whoever owns the bake listens to `controller.events`
  (`PanelCatalogScrollingChanged`, `PanelCatalogScrollSettled`) and calls
  `GlyphAtlas.reportScrolling` / `prioritise`. The glyph paragraph cache and
  `kGlyphParagraphCacheLimit` are gone: the scope's byte-budgeted LRU bounds
  the paragraphs of the text strategy (section headers keep a bounded cache).
- **The bake pause is event-driven.** `CatalogBakeActivity` derives its two
  outputs from the controller's events instead of the paint offset and
  publishes them as `PanelCatalogScrollingChanged` and
  `PanelCatalogScrollSettled(visibleKeys)`.

### Added

- `CatalogContentBox` and the per-section overrides `CatalogSection.contentBox`
  and `CatalogSection.placeholderStyle`: the square a leaf is asked for from the
  cache and drawn in (the glyph box for emoji, the whole cell for a sticker,
  mask or GIF) and its stand-in, which a section can state instead of taking
  the leaf's facts.
- `SectionLayout`, `CatalogLeafHit`, `CatalogPlaceholderStyle`,
  `catalogGlyphBoxExtent` and `largestCatalogGlyphBox`: the rule that sizes a
  single baked glyph size for sections with different cell sizes.
- `PanelCatalogUserDragCancel`, `PanelCatalogScrollingChanged`,
  `PanelCatalogScrollSettled` scroll events; `PanelCatalogController` extents
  (`viewportExtent`, `contentExtent`, `maxScrollExtent`, `hasPosition`).

- **Baked sprites on screen.** A binding whose paintable has a sprite (a baked
  glyph on an atlas page) is queued by the painter, and one paint pass draws
  every page's sprites with a single batched atlas draw (the pressed cell is
  scaled inside its batch). A paintable without one paints itself, which is the
  web strategy.
- **`panel_catalog_diagnostics.dart`** — `PanelCatalogDiagnostics.glyphParagraphDraws`,
  the proof that no emoji is drawn as text where emoji are baked (`0`). Bumped
  only for a glyph a paintable draws as text, so the sprite path pays nothing.
- **Bake stays out of the way.** The viewport publishes when it scrolls (drag,
  fling, jump, wheel, section motion) and, once it settles, which glyphs are on
  screen, so the bake's owner can pause it and bake the visible page first.

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
