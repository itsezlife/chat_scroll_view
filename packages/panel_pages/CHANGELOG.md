# Changelog

All notable changes to `panel_pages` are documented in this file. The format is
loosely based on [Keep a Changelog](https://keepachangelog.com/); this package
is pre-1.0.

## [Unreleased]

### Added

- `CatalogPage`, the page scaffold: viewport hosting on collections, loading
  and paging as sections come near, search results over a `SearchSource`, pick
  and long-press plumbing, a top strip slot, roving-focus keys, scroll-activity
  reporting to the shell and the bake hand-off.
- `CatalogPagePolicy` for the decisions that depend on the kind of content, and
  `CatalogPageModel` / `CatalogSnapshotBuilder` for the state and the
  collection-to-section mapping behind the widget.
- `BakeActivityPort`, `CatalogBakeForwarder` and `GlyphAtlasBakePort`: the
  catalogue's motion (as one reporter, with union semantics) and its settled
  visible band reach the glyph bake through a narrow port that survives a
  replaced atlas. Replaces the forwarding the old chrome package did.
- `ChromeCatalogTheme`, the single mapping of chrome tokens to the viewport's
  own theme; `PageAssets`, the scope that draws glyphs as text where nothing is
  baked.
- `package:panel_pages/testing.dart` with `FakePanelPageHost`,
  `FakeBakeActivityPort` and `runBakeActivityPortContract`.
- `EmojiPage`, the emoji page, over `CatalogPage`: `EmojiPagePolicy` (eight
  columns, category titles from the panel strings, recents only while there
  are some and alone for an empty search, a header action that asks the host to
  clear them, a long-press variant picker), `EmojiCategoryStrip` (one tab per
  category, active tab follows the catalogue, landing rules), `EmojiVariantPicker`
  and `EmojiVariantSession` (an entry's base and variants, chosen by sliding or
  tapping, remembered per base through `PreferenceStore`) and `EmojiTabIconScope`
  (the strip's Telegram art as chrome icon painters).
- `GlyphAtlasHost` and `GlyphPlan`: the atlas of a page that shows baked glyphs,
  planned from the glyph list of the page's collections (the chosen variant of
  each emoji, then recents the catalogue lacks, sorted, so a pick never
  re-bakes), replanned behind the old art, wired to the panel's visible and
  opening observables. Replaces `EmojiGlyphAtlasHost` of the old chrome package
  with its behaviour tests. `EmojiPageController` keeps it across the page
  widget being torn down.
- The paced cold mount: `EmojiPage.deferChrome` mounts the grid, and the strip two
  frames later (the frame between is `PanelShell.deferSearchField`'s).

### Changed

- `CatalogPagePolicy.actionOf` takes the panel strings, so a header action is
  labelled in the host's language.
- `CatalogStripHandle` has `currentSectionId`, for a strip that mounts after the
  catalogue laid out.
- `CatalogPageController` is a `base class` so a page can keep more than the
  catalogue under its page id (the emoji page keeps its atlas host).
- `CatalogPage` releases the search focus (`PanelPageHost.releaseSearchFocus`)
  when the user takes hold of the catalogue.
- `FakePanelPageHost` has `visible`, `opening` and counts focus releases.
