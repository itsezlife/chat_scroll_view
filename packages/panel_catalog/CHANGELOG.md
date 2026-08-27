# Changelog

All notable changes to `panel_catalog` are documented in this file. The format
is loosely based on [Keep a Changelog](https://keepachangelog.com/); this package
is pre-1.0.

## [Unreleased]

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
  ([kFarPathDistanceGateFactor]), not `spanCount × 9` rows. Matches Telegram
  `EmojiView.scrollEmojisToPosition` (`spanCount × 9` in per-cell adapter
  space). The previous multiplier over-widened near-path smooth scroll.
- **`PanelCatalogController.jumpToSection` re-entry** — while
  [isSectionJumpActive], additional requests are ignored and return the
  in-flight future (Telegram `emojiSmoothScrolling` /
  `fastScrollAnimationRunning`); user drag still cancels.
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
