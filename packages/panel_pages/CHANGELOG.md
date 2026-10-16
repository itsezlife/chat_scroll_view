# Changelog

All notable changes to `panel_pages` are documented in this file. The format is
loosely based on [Keep a Changelog](https://keepachangelog.com/); this package
is pre-1.0.

## [Unreleased]

### Added

- The sticky header. `CatalogPage` draws the policy's strip over the catalogue,
  where it slides away as the user reads on and returns as they read back, and,
  for a page whose capabilities say `SearchPlacement.inline`, the shell's search
  field as the first thing in the content (it scrolls away, and pins when search
  opens). The catalogue is padded by their extent and section jumps land under
  the strip. The geometry is `CatalogStickyHeader`, a pure class.
- `CatalogPagePolicy.stripExtent`: the height of the strip the policy builds
  (0, the default, for none). A policy that builds a strip must declare it.
- `CatalogPage.searchFieldReady`, and `FakeSearchFieldScope` in
  `package:panel_pages/testing.dart` for tests that mount a page without a
  shell.

### Changed

- `EmojiPagePolicy.pageCapabilities` places the search field inline.
  `EmojiPage.deferChrome` paces the field and then the strip, one frame each
  after the grid, as the panel did.
- The category strip no longer draws a hairline of its own (the page draws it
  while content passes under the strip), and its selected wash is the idle icon
  colour at 18 % alpha again.

### Changed

- Change notification is `package:listen` (`listen: ^1.0.1`), not
  `content_model`'s removed `Observable` family: `CatalogStripHandle.entries`,
  `GlyphAtlasHost.atlas` and the presence inputs are `ValueListenable`s (the
  `package:listen` type, not Flutter's), `CatalogStripHandle.scrollEvents` is a
  `Stream<PanelCatalogScrollEvent>`, and the scroll reporter, bake forwarder
  and page model subscribe to the catalogue's event stream and cancel in
  `dispose`. `FakePanelPageHost` is a `ChangeNotifier` whose `dispose` stays
  idempotent.

### Fixed

- The category strip slides a tab into view on the `fade` motion role (and lands
  at once under an instant speed) instead of a literal 200 ms.
- Closing the panel no longer turns the glyphs of surfaces outside it (the
  composer's inline emoji, drawn through the same scope) into circles: the
  emoji page leaves its atlas registered with the scope when it unmounts and
  the shell's controller takes it out when disposed. Until the atlas is
  planned (a source that lists its collections late) the glyphs shown are
  circles that move onto it, not paragraphs.

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
  (the strip's art as chrome icon painters).
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
