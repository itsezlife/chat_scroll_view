# Changelog

All notable changes to `panel_pages` are documented in this file. The format is
loosely based on [Keep a Changelog](https://keepachangelog.com/); this package
is pre-1.0.

## [Unreleased]

### Added (the pointer policy)

- `CatalogPointerPolicy` (`.desktop()`, `.web()`, `current`): what a page offers a mouse for taking content out of the library, as properties: `packHeaderRemoves` (an installed pack's header cross) and `removeBadge` (the hovered cell's badge look). The pages read `CatalogPointerPolicy.current` where they read the platform before; the header cross's helper takes a policy instead of a web flag. Behaviour unchanged.

### Added (the emoji pack sheet's preview)

- `EmojiPackSheet.previews` and `onCopyRequested`: a custom emoji held in an emoji pack sheet or box opens the content preview, as on the panel's emoji page (from frame 0, switching under the finger or pointer, Send Emoji and Copy Emoji); a right-click in the box offers Copy Emoji. A tap still inserts.

### Changed (the web's header cross)

- The remove cross of an installed pack's header is a desktop's only; the web's headers keep the recents' cross alone.

### Changed (desktop panel and pack box)

- Under a pointer: the sticker pack strip sits at the bottom as the emoji footer; an installed pack's header ends in a remove cross (`LibraryEdit.removePack`); recent and favourite stickers and saved GIFs show a remove badge on hover; a custom emoji's secondary click offers Copy emoji; a mouse preview has no menu and slides between GIFs.
- The GIF page decodes a clip for its own proportions (a resized page plays on) and groups its rows at a fixed 334 under a pointer (a resized page keeps its rows); a GIF cell answers a press with `ChromeInk`.
- The pack box under a pointer: five 64 px sticker cells or eight 42 x 39 emoji cells, the grid at most 320 or 197 tall, a 42 px button with the pack's count in a badge. `ChromeCatalogTheme.hoverSize`.

### Fixed (a strip keeps its covers through a close and an open)

- A pack strip's playing covers hold their frames and leases while the
  panel moves or is hidden, as the grid's cells do, instead of letting them
  go: with the chat's stickers filling the frames kept for the screen, the
  covers lost theirs on every close and showed their stills on reopening.

### Fixed (the grid under a content preview; one haptic for a tap)

- While a content preview is open over the panel's grid or a pack sheet's,
  the cells show no press or hover wash; a sticker's cell the preview shows
  is drawn smaller and follows the finger (`CatalogLeafPreview`). A custom
  emoji's and a GIF's cells keep their size.
- A sticker tapped in a pack sheet, which opens its preview with the menu at
  once, plays one haptic (the menu's), not two.

### Fixed (a pack sheet follows the finger past its grid)

- A pull down on a bottom pack sheet's grid at its top, or anywhere on its
  header band, lowers the sheet and closes it past 0.8 cm or on a fast
  flick; a shorter pull springs back. Before, the grid took every drag over
  it and dropped what it could not scroll, so only the title's own glyphs
  moved the sheet. A push up first undoes the pull, then raises the card.
  A scroll that reaches the top moves the sheet on the same tick; it
  closes on the pull's own speed, so a fast scroll that runs a little past
  the top and slows springs back. Sticker and emoji
  sheets alike; the box under a pointer is unchanged.

### Fixed (sheet and menu typography, menu icons)

- The pack sheet, the content preview and the pickers and tooltips placed in
  an overlay draw their text in the host's body face (`ChromeTypography`)
  rather than the style inherited where they open. That style was the
  framework's debug one (monospace, weight 900) whenever the opener had no
  `Material` above it; `PackSheet.show` no longer captures it. The sheet's
  bold texts are weight 500, the medium face (Roboto Medium), not
  600 (native-media ticket 140).

### Added (menu icons)

- Each content preview menu item leads with its icon
  (`ContentPreviewAction.icon`: `msg_send`, `input_notify_off`, `msg_fave`,
  `msg_unfave`, `msg_media`, `msg_delete`, `msg_gif_add`, `msg_copy`),
  16 px regular text 43 past the icon's start. `CatalogMenuIcons`
  names the ids and bundles the art (`assets/menu_icons/`);
  `CatalogMenuIconScope` registers it. `CatalogMenuItem.icon` puts an icon on
  a context menu item, and the preview's right-click entries carry theirs.

### Added (a pack sheet's route is named)

- `PackSheet.routeName`: the `RouteSettings.name` of the route
  `PackSheet.show` pushes, in either arrangement (was unnamed). A host that
  pauses its animations under modal routes tells the sheet apart by it, so
  the sheet's stickers and the preview opened from it play (native-media ticket 128).

### Fixed (GIF preview swipe settles)

- A GIF dragged up until its menu opens now moves back to its resting place
  over 350 ms on the standard ease curve; the menu stays open.

### Fixed (pack sheet text and focus)

- A pack sheet's text no longer falls back to the debug style (yellow double
  underline, fallback font): both routes take the text style of the context
  that opened the sheet, in the chrome palette's `onSurface`.
- Opening a pack sheet no longer takes focus from the composer, so a raised
  keyboard stays up; the sheet lays out above the keyboard (view insets).
  Back and the barrier still dismiss it.

### Changed (pack sheet parity)

- A tall pack sheet on touch now opens with its card two fifths down the
  screen (an emoji sheet at 0.56 of it, 0.3 in landscape) and rises as its
  grid scrolls, until the card meets the status bar; then the grid scrolls
  under the pinned header, whose shadow line fades in over 150 ms. Before, it
  opened at a fixed 3/5 of the screen and only its grid scrolled. A press
  above the card closes the sheet. A sticker card's 12 px top corners square
  as it reaches the status bar, which its background then covers; an emoji
  card's 14 px corners do the same over 350 ms.
- A pack's header in a sheet of several emoji packs is 56 px: its title (17
  bold), its count (`PackSheetStrings.emojiCount`, 13) and a 28 px button,
  an Add pill or a Remove text button, which trade places with a 250 ms
  fade and scale when the pack's install state changes. The sheet draws
  these headers over the grid; the grid's section headers are blank bands.
- A right-click on a sticker of a sheet given `previews` opens the preview's
  items as a context menu, as the panel's grid does.
- `EmojiPackSheet.previewEmoji`: the emoji a sheet was opened for (a custom
  emoji tapped in a message), drawn 140 px large 20 px above the card on
  touch and moving with it. It fades out (320 ms, shrinking to 0.6) for good
  once the user scrolls the grid, the sheet closes, or the card's top is
  less than 160 px from the top of the screen.
- `CatalogContextMenuHost.host` may be null, for a grid outside the panel
  with no auto-hide to hold.

### Added (pack sheets)

- `StickerPackSheet` and `EmojiPackSheet` (one pack or several), shown with
  `PackSheet.show`: a bottom sheet on touch (dim `0x33`, opening in 420 ms
  on ease-out-quint after 20 ms, closing in 250 ms, dismissed by a drag past
  0.8 cm or a 3500 px/s fling, part-way when taller than 3.2/5 of the
  screen) and a centred 364 px box under a pointer. They read a
  `PackSource` and the library's install states and ask the host for every
  effect (`PackEditsRequested`, `onPick`, `onUnavailable`, `PackSheetLinks`).
  The bottom button is a `PackSheetAction`. A sticker sheet given `previews`
  opens the content preview on a hold and, with its menu, on a tap.
- `CatalogPagePolicy.titleActionOf`: a section's title as an action. The
  stickers and emoji pages report a tap on a pack's title as
  `PanelPageHost.requestPack`.

### Added (content preview)

- `ContentPreviewSession`: the content preview, a
  `CatalogLongPressSession` that shows a sticker, GIF or custom emoji large
  over a dim of the window (never a unicode emoji), follows a finger from cell
  to cell (a GIF drags up to open its menu instead), opens its menu after
  1.3 s (a GIF 2 s), and closes on a lift before the menu, on an item, on a
  press elsewhere or on the host's back. A mouse holds 500 ms and gets no
  menu. `ContentPreviewSession.show` is the entry point for any grid; a pack
  sheet opens it with a send action and `openMenu` for a tap.
- `ContentPreviewItem`, `ContentPreviewKind`, `ContentPreviewLayout` (the
  geometry), `ContentPreviewMenu` and `ContentPreviewAction` (the
  items per kind, their labels and what each asks), `ContentPreviewActions`
  (what the opener can do), `ContentPreviewController` (the host's handle:
  the library the menus read, and `dismiss` for back),
  `CatalogContentPreview` (a grid's delegate for long press and context menu)
  and `panelPreviewActions` (the panel host's requests).
- `StickersPage`, `GifPage` and `EmojiPage` take an optional `previews`:
  given, a held sticker (favourites and recents included), GIF or custom
  emoji previews, and a right click on a sticker or GIF opens the preview's
  items as a context menu. Without it nothing changes.
- `FakePanelPageHost.libraryEditRequests` and `packRequests`.

### Changed (content preview)

- `CatalogPagePolicy.beginLongPress` takes an optional `leafAt` (the
  catalogue's `PanelCatalogController.leafAt`); a policy that overrides it
  must add the parameter.
- `StickersPagePolicy` takes `host` and `previews`, and tags a sticker cell
  with its pack (`StickerPackTag`).

### Added (favourite stickers)

- The stickers page shows a favourites section, `CollectionId.faved` from its
  source, titled `PanelStrings.favouriteStickersTitle` and hidden while known
  to be empty as the recents are, with no header button; a pick from it is a
  pick from a collection. Its strip has a tab for it, drawn by
  `StickerPackStrip.favouritesIcon` (the `emoji_tabs_faves` asset, now
  bundled and registered by `EmojiTabIconScope`), and the tabs follow the
  order of the sections, so a source that lists the favourites first starts
  the strip on them. Requires `PanelStrings.favouriteStickersTitle`.
- A pack tab whose cover is not known yet draws nothing until it is; it drew
  the recents' icon.

### Changed (a fresh open)

- A page comes back from a close as the presentation's **fresh open**
  (`PanelPageHost.freshOpen`) says, not as the arrangement does. On a fresh
  open (the mobile keyboard replacement) the stickers page goes back to its
  start with its strip whole and its first tab (the recents, else the first
  pack) marked, and the GIF page goes back to its start, both whether or not
  they are mounted then; the emoji page keeps its place. An open that is not
  fresh (a popup, a dock) keeps the place of every page. Before, every
  catalogue page went back to its start whenever the panel was hidden under
  `touch`, the emoji page among them.
- Removed `CatalogPage.keepsScrollOnReopen` and
  `EmojiPage.keepsScrollOnReopen`; a page's policy says whether it restarts
  (`CatalogPagePolicy.restartsOnFreshOpen`, false by default, true for
  `StickersPagePolicy`). `CatalogPageController.followPresence` and
  `restartsWhenHidden` are now `followFreshOpen` and `restartsOnFreshOpen`.
- `FakePanelPageHost.openAfresh` signals its `freshOpen`.

### Changed (small covers at half rate)

- A pack strip's playing cover comes from `AssetPresets.keyboardCell`, which
  now plays a cell of up to 90 logical px at half rate and decodes it at most
  160 px on a side; the strip's code is unchanged.

### Changed (pack strip covers)

- `StickerPackStrip` plays a pack's animated cover in its tab, looping; before, a tab showed the cover's first frame.
  It plays on the shared playback clock, so the clock's pause layers (low
  power among them) stop it, and only while its tab is in the strip's view: a
  tab scrolled away stops repainting and gives its frame slot back. A still
  cover stays still. Covers are decoded at their size on the screen
  (`AssetPresets.keyboardCell`, 26 times the density), as the other animated
  cells are, and now ask for the whole asset (`AssetVariant.full`), not the
  first frame, so a host's decoder sees full requests for them.

### Added (pages with nothing to list)

- `StickersPage` says `PanelStrings.stickersEmpty` in the middle of the page
  when it has nothing to list: the recents known to be empty and no pack.
  Before, such a page was blank.
- `GifPage` says `PanelStrings.gifsEmpty` when every collection has loaded
  and none has a clip to list (no recents, no provider), not only when a
  search found nothing. A page still loading says nothing; one whose load
  failed keeps its failure line. Requires `PanelStrings.stickersEmpty`.

### Changed (GIF cells)

- A GIF cell waits as the whole rectangle of its final size and proportion
  in the skeleton token, with the radial progress over it until the clip has a
  first frame, instead of a grey circle; the clip and its thumbnail fill the
  cell and are cropped at the edge.

### Added (GIF page search and empty states)

- `GifPage` takes an optional `searchSource` (a `SearchSource`), `searchDebounce`
  and `attribution`. Given a source, the page follows the shell's search (the
  host's `PanelPage` declares `PageCapabilities(search: true)`) and lists the
  results in place of the collections, paged as the end comes near. A
  collection or search that failed ends the list with a retry button; a search
  that found nothing says so; the attribution heads the list. Existing hosts
  are unchanged: without a `searchSource` there is no search, and a failed
  collection, which showed nothing before, now shows the failure line.
- Requires `PanelStrings.gifsEmpty`, `gifsFailed` and `retryAction` from
  `chrome_foundation`.

### Added (stickers and GIF pages)

- `StickersPage` with `StickersPagePolicy` and `StickerPackStrip`: the
  sticker list (columns from the width at 72, rows 82,
  stickers at most 66, headers 27 tall beginning 15 in) under a strip of packs
  whose tabs are covers, with a clear button on the recents header.
- `GifPage` with `GifRowLayout`: justified rows of GIFs.
- `CatalogPagePolicy.headerStartInset` (default null: the viewport's), and
  `ChromeCatalogTheme` takes it. A policy of a list whose titles begin
  somewhere else says so; existing policies are unchanged.
- Requires `SemanticsStrings.stickerPackStripLabel` from `chrome_foundation`.

### Changed

- `EmojiTabIconScope` leaves a tab to the host when the enclosing
  `ChromeIconScope` already paints its id, so a host restyles the strip's
  tabs by registering painters above it (the strip mounts its own scope).
- Under the touch arrangement, `EmojiCategoryStrip` follows `EmojiStripLayout`
  too: with a pack (by default) it is the touch strip with
  custom emoji: the recents, the categories folded into a group that opens
  while one of them is active, then a tab per pack drawn by its cover. Without
  a pack, or with `EmojiStripLayout.plain`, it is the row of category tabs as
  before. Hosts that relied on the touch strip never showing packs pass
  `EmojiStripLayout.plain`.
  A pack's tab is its cover's first frame, a still, as the strip draws it; the pill stays still on the open group while the category inside
  it changes.
- `EmojiPagePolicy` files every pick under `EmojiPagePolicy.recentsKind`
  (`SemanticKind.unicodeEmoji`), custom emoji included: the page has one
  recents list. The list is the pick's new
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
- The tone-for-all button draws a sliders icon.
- The bands over the catalogue and the touch strip paint the shell's
  background, and the catalogue is clipped below them.
- A header lands at the page's top padding plus an overlaying strip, never
  under a field that scrolls away.
- The plain strip has 30 px slots, nothing folded.
- Under `pointer` the Smileys & People header has the tone-for-all button
  (`EmojiPagePolicy.colorAllActionId`); `EmojiVariantPicker` takes a `title`.
- Source-breaking: `CatalogPagePolicy.onSectionAction` takes `context`,
  `bounds` and `viewportBounds`.
- Anything but a mouse gets the touch tone picker
  (`EmojiToneSession`, `EmojiTonePicker`, `EmojiTonePickerLayout`), with
  haptics and a two-person picker.
- `EmojiStripLayout` (`automatic`, `plain`, `grouped`) on
  `EmojiCategoryStrip.layout`, `EmojiPagePolicy.stripLayout` and
  `EmojiPage.stripLayout`: plain with no pack and grouped with any by default,
  as the default rule decides.
- The strip's group opens linearly over 240 ms and the marker grows inside it
  on an exact ease-out cubic.
- Under `pointer` the catalogue's hover is a 34 x 32 box and a press draws
  nothing (`ChromeCatalogTheme.pointerHoverSize`); the variant picker draws
  the same box (`EmojiVariantPicker.highlightSize`).
- Source-breaking: under `pointer` the emoji strip is the footer with packs (`EmojiStripFooter`): no line over it, 30 px
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
- The emoji tabs follow the seven categories
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
