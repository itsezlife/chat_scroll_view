# Changelog

All notable changes to `panel_catalog` are documented in this file. The format
is loosely based on [Keep a Changelog](https://keepachangelog.com/); this package
is pre-1.0.

## [Unreleased]

### Added

- **`PanelCatalogController.jumpToSection`** — programmatic section landing
  under viewport top inset with near-path smooth scroll when the far-path
  distance gate passes (`spanCount × 9` flat-row rule,
  [kFarPathDistanceGateFactor]). Exposes [isSectionJumpActive] for host
  strip-sync gating during programmatic motion.
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
  `CatalogLeafPress`; test seams `pressedLeaf` / `pressProgress` on the render
  object.
- **Ballistic fling** — `CatalogScrollPhysics` (`ClampingScrollSimulation`) on
  drag-end; pointer-down while flinging cancels coast and suppresses leaf
  tap/long-press for that pointer (no accidental insert while stopping scroll).
- **Widget tests** — fake data source + stub asset cache at the public viewport
  API (scroll, notify, placeholders, hit-test, fling cancel).

### Dependencies

- `catalog_assets` for process-wide asset readiness and attach/refcount.
