# Changelog

All notable changes to `panel_pages` are documented in this file. The format is
loosely based on [Keep a Changelog](https://keepachangelog.com/); this package
is pre-1.0.

## [Unreleased]

### Changed

- `EmojiTabIconScope` leaves a tab to the host when the enclosing
  `ChromeIconScope` already paints its id, so a host restyles the strip's
  tabs by registering painters above it (the strip mounts its own scope).
- Under the touch arrangement, `EmojiCategoryStrip` follows `EmojiStripLayout`
  too: with a pack (by default) it is the reference mobile client's strip with
  custom emoji: the recents, the categories folded into a group that opens
  while one of them is active, then a tab per pack drawn by its cover. Without
  a pack, or with `EmojiStripLayout.plain`, it is the row of category tabs as
  before. Hosts that relied on the touch strip never showing packs pass
  `EmojiStripLayout.plain`.
  A pack's tab is its cover's first frame, a still, as the reference client
  draws it; the pill stays still on the open group while the category inside
  it changes.
- `EmojiPagePolicy` files every pick under `EmojiPagePolicy.recentsKind`
  (`SemanticKind.unicodeEmoji`), custom emoji included: the page has one
  recents list, as the reference clients do. The list is the pick's new
  `recentsKind`; its `kind` stays the content's own, so a custom emoji pick
  is still `SemanticKind.customEmoji`. A host that recorded recents under
  `kind` records them under `recentsKind`. The recents menu and the finger's
  clear-on-long-press answer on a custom emoji of the recents too; the menu's
  copy asks under the content's own kind (`ContentCopyRequested.kind`).
- Source-breaking: `CatalogPick` has `recentsKind` (its `kind` when omitted),
  passed on to `PanelPageHost.pick`, and `FakePanelPageHost.picks` records
  carry it: a test that compares whole records names it.
- Source-breaking: `emojiVariantOptions(entry)` is
  `EmojiVariantPicker.optionsOf(entry)`, and `runBakeActivityPortContract(...)`
  in `testing.dart` is `BakeActivityPortContract.run(...)`.
- The two-person tone picker shows each tone as the emoji with both people
  in it (for two hands, the one-tone sequence), the other person greyed;
  choosing the same tone for both keeps that one-tone sequence. No blank cells.
- The tone-for-all button draws the reference desktop client's sliders icon.
- The bands over the catalogue and the touch strip paint the shell's
  background, and the catalogue is clipped below them.
- A header lands at the page's top padding plus an overlaying strip, never
  under a field that scrolls away.
- The plain strip has 30 px slots, nothing folded.
- Under `pointer` the Smileys & People header has the tone-for-all button
  (`EmojiPagePolicy.colorAllActionId`); `EmojiVariantPicker` takes a `title`.
- Source-breaking: `CatalogPagePolicy.onSectionAction` takes `context`,
  `bounds` and `viewportBounds`.
- Anything but a mouse gets the reference mobile client's tone picker
  (`EmojiToneSession`, `EmojiTonePicker`, `EmojiTonePickerLayout`), with
  haptics and a two-person picker.
- `EmojiStripLayout` (`automatic`, `plain`, `grouped`) on
  `EmojiCategoryStrip.layout`, `EmojiPagePolicy.stripLayout` and
  `EmojiPage.stripLayout`: plain with no pack and grouped with any by default,
  as the reference desktop client decides.
- The strip's group opens linearly over 240 ms and the marker grows inside it
  on an exact ease-out cubic.
- Under `pointer` the catalogue's hover is a 34 x 32 box and a press draws
  nothing (`ChromeCatalogTheme.pointerHoverSize`); the variant picker draws
  the same box (`EmojiVariantPicker.highlightSize`).
- Source-breaking: under `pointer` the emoji strip is the reference desktop
  client's footer with packs (`EmojiStripFooter`): no line over it, 30 px
  slots from 3 px in, the categories folded into one icon that opens into
  theirs while one is active, a slot per pack (`CollectionId.set` sections,
  drawn by their cover from `EmojiCategoryStrip.assets`), wheel and drag
  scrolling, centring, edge fades. `EmojiCategoryStrip.separatorExtent`,
  `highlightSize`, `highlightRadius`, `pointerPadH` and `pointerMinPitch` are
  gone; `EmojiPagePolicy` takes `assets`.
- Under `pointer` an emoji is drawn at 24 px at every width, in the grid and
  the variant picker (`EmojiPagePolicy.pointerGlyphSize`); the picker takes
  the grid's `glyphExtent`.
- Source-breaking: `GlyphAtlasHost` is the page's `BakeActivityPort` and has a
  `source`, the layered glyph source the scope draws from. A plan with new
  glyphs no longer plans the atlas again: an atlas of just those glyphs joins as
  a layer, nothing baked is baked again, the persisted pages keep their key, and
  no glyph leaves the source (a composer's emoji of an earlier tone stays
  drawn). `atlas` is the first atlas; only a density change replaces it.
- Source-breaking: `CatalogPagePolicy.layoutOf` takes the arrangement. Under
  `pointer` the emoji grid is adaptive (37 px desired cells, 2 px shorter than
  wide), padded 8 from the start and 4 from the end.
- A mouse on an emoji with variants always holds 500 ms before the picker
  opens; `EmojiVariantPickerMode.pointerImmediate` is gone.
- The context menu opens with no item highlighted; Down highlights the first,
  Up the last.
- The variant picker and the context menu are part of the composer's tap
  region, so a click on them keeps the composer's focus.
- Source-breaking: `CatalogPagePolicy.visibleCollections` takes no `searchOpen`
  flag. An open search with no query shows what browsing shows, under both
  arrangements, and the emoji page no longer narrows to the recents.
- The emoji recents header has no clear button. A finger's long press on a
  recent asks the host to clear them (`requestClearRecents`) instead of
  opening the variant picker; a mouse keeps the hold and the right-click menu.
  `EmojiPagePolicy.clearRecentsActionId` is gone.
- Under `pointer` an `inline` search field is the page's, scrolls with the grid
  and does not pin.
- The emoji tabs follow the reference client's seven categories
  (`EmojiSection.reference`): the flags have no tab and the ids are
  `people`, `nature`, `food`, `activity`, `travel`, `objects`, `symbols`;
  activity comes before travel. Hosts that supply strings key
  `PanelStrings.categoryTitle` by those ids.

### Added

- `PageAssets.createScope(systemFonts:)`, passed to the scope: a host that
  draws glyphs as text (the web) passes the engine's signal so glyphs laid out
  before the emoji font arrived are laid out again.
- `PageAssets.createScope(textGlyphsReady:)`, handed to
  `TextGlyphProducer.fontsReady`: placeholders until the fonts that draw the
  glyphs are there.

- `EmojiTabIcons.clearCache()` (`@visibleForTesting`): forgets the decoded
  tab art, for tests sharing one process (`test/unit_test.dart`), where a
  scope opened under fake async leaves a decode that never completes.
- `CatalogPage.keepsScrollOnReopen` and `EmojiPage.keepsScrollOnReopen`:
  whether the catalogue is where it was left when the panel is shown again.
  By default it goes back to its start under `touch` and keeps its place
  under `pointer`. A tab switch or a swipe keeps the place either way.
  `CatalogPageController` follows the shell's presence
  (`followPresence`, `restartsWhenHidden`) and resets when the panel is
  hidden, whether or not the page is mounted.

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
- The sticky header, under `touch` (what `PanelArrangementScope` answers where
  no shell is above). `CatalogPage` draws the policy's strip over the
  catalogue, where it slides away as the user reads on and returns as they read
  back, and, for a page whose capabilities say `SearchPlacement.inline`, the
  shell's search field as the first thing in the content (it scrolls away, and
  pins when search opens). The catalogue is padded by their extent and section
  jumps land under the strip. The geometry is `CatalogStickyHeader`, a pure
  class. Under `pointer` there is no sticky header: the strip is a part of the
  column (above the catalogue, or pinned below it where `stripAtBottom`) and
  the shell draws the search field whatever placement the page declared. A page
  moved from one arrangement to the other (a popup docked in place) takes the
  other layout in place.
- `CatalogPagePolicy.stripExtent`: the height of the strip the policy builds
  where it is a sticky header (0, the default, for none). A policy that builds
  a strip it keeps at the top under `touch` must declare it; one pinned at the
  bottom is measured instead.
- `CatalogPage.searchFieldReady`, and `FakeSearchFieldScope` in
  `package:panel_pages/testing.dart` for tests that mount a page without a
  shell.

### Changed

- Choosing an emoji as it is in the picker is remembered as the base itself
  (`PreferenceStore.preferredVariant(base) == base`), so the next press can tell
  the user has chosen. The grid shows the same emoji.
- `EmojiPagePolicy.pageCapabilities` places the search field inline (honoured
  under `touch`; under `pointer` the shell draws it).
  `EmojiPage.deferChrome` paces the field and then the strip, one frame each
  after the grid, as the panel did.
- The category strip's touch form no longer draws a hairline of its own (the
  page draws it while content passes under the strip), and its selected wash is
  the idle icon colour at 18 % alpha again. The pinned (pointer) form is
  unchanged.
- Change notification is `package:listen` (`listen: ^1.0.1`), not
  `content_model`'s removed `Observable` family: `CatalogStripHandle.entries`,
  `GlyphAtlasHost.atlas` and the presence inputs are `ValueListenable`s (the
  `package:listen` type, not Flutter's), `CatalogStripHandle.scrollEvents` is a
  `Stream<PanelCatalogScrollEvent>`, and the scroll reporter, bake forwarder
  and page model subscribe to the catalogue's event stream and cancel in
  `dispose`. `FakePanelPageHost` is a `ChangeNotifier` whose `dispose` stays
  idempotent.

### Fixed

- The tone-for-all icon strokes its lines and rings as one path, so a
  translucent colour is no brighter where a line meets its ring.

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
