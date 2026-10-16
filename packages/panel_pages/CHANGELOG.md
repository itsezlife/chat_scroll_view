# Changelog

All notable changes to `panel_pages` are documented in this file. The format is
loosely based on [Keep a Changelog](https://keepachangelog.com/); this package
is pre-1.0.

## [Unreleased]

### Added

- The recents context menu ([ADR 025](../../docs/adr/025-panel-shell-and-pages.md)
  amendment): `CatalogPagePolicy.menuOf` / `onMenuAction` with the declarative
  `CatalogMenuEntry` (`item`, `separator`), drawn by `CatalogContextMenuHost`
  (built on `RawMenuAnchor`; modal, with Escape, arrows and Enter, taking
  focus and giving it back, holding auto-hide while open). The emoji policy
  offers copy, remove from recent and clear recent on a recent emoji under the
  pointer arrangement. `CatalogPagePolicy.actionOf` takes the arrangement; the
  emoji policy has no recents header action under `pointer`.
- `CatalogPagePolicy.longPressDelayOf(hit, collection, kind)`; the emoji policy
  opens the picker at once under a mouse for an emoji whose variant was never
  chosen and after 500 ms otherwise. `CatalogLongPressSession.isOpen` (a
  session may outlive the gesture; the page pins the cell meanwhile) and
  `beginLongPress` takes the pointer kind and the pressed cell's and the
  viewport's global bounds. Source-breaking for a policy that overrides them.
- `EmojiVariantPickerLayout`, `EmojiVariantPickerMode` and a rewritten
  `EmojiVariantPicker` / `EmojiVariantSession`: the grid's own cell and glyph
  box for every option, 8 px pads, a separator after the first, above the
  pressed cell or below near the top, proportional to the column, 200 ms fade,
  modal on a barrier, holding auto-hide. Replaces `EmojiVariantPickerMetrics`
  and the arrow.
- `ChromeCatalogTheme.hoverWashOf(palette)`; goldens for the menu and the picker
  under a mouse were generated on macOS.
- The pointer arrangement of `PanelShell` ([ADR 025](../../docs/adr/025-panel-shell-and-pages.md)
  amendment). `CatalogPagePolicy.stripAtBottom(arrangement)` (default false;
  the emoji policy answers true for `pointer`) puts the strip below the
  catalogue and makes `CatalogPage` report its measured height through
  `PanelPageHost.reportBottomExtent` (0 while results or a single category
  show no strip, and when the arrangement moves it back). The emoji strip
  pinned at the bottom is a 1 px separator over 36 px of icons on
  `PanelTokens.stripFill`, the icons spread over the width (scrolling below
  33 px each), the active category marked by a 28 px square of radius 8 that
  slides over the `selectionSlide` motion role (placed on the first
  selection, at once without animations), no hover paint, a click cursor.
  `EmojiCategoryStrip.separatorExtent`, `highlightSize`, `highlightRadius`.
- Under `pointer` an empty query with search open does not narrow the page: the
  whole catalogue and the strip stay and one press of the clear control brings
  the grid back. `CatalogPageModel.arrangement`; under `touch` the policy is
  asked with `searchOpen` as before.
- `ChromeCatalogTheme.dataFor(chrome, arrangement:)`: under `pointer` the
  catalogue paints a hover wash (the text colour at alpha `0x12`).
- `FakePanelPageHost.bottomExtents`.

### Changed

- Choosing an emoji as it is in the picker is remembered as the base itself
  (`PreferenceStore.preferredVariant(base) == base`), so the next press can tell
  the user has chosen. The grid shows the same emoji.
- Change notification is `package:listen` (`listen: ^1.0.1`), not
  `content_model`'s removed `Observable` family: `CatalogStripHandle.entries`,
  `GlyphAtlasHost.atlas` and the presence inputs are `ValueListenable`s (the
  `package:listen` type, not Flutter's), `CatalogStripHandle.scrollEvents` is a
  `Stream<PanelCatalogScrollEvent>`, and the scroll reporter, bake forwarder
  and page model subscribe to the catalogue's event stream and cancel in
  `dispose`. `FakePanelPageHost` is a `ChangeNotifier` whose `dispose` stays
  idempotent.

### Fixed

- The variant picker no longer crops its glyphs. A colour emoji font draws
  bitmaps larger than the em box it lays out, and the old picker clipped each
  option to a 32 px rounded container (four of six options of a test set were
  cut at the edge with Apple Color Emoji). Options are the grid's cell with
  the grid's glyph box and font scale, and nothing clips. The arrow is gone.
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
