# Changelog

All notable changes to `attach_sheet` are documented in this file. The format
is loosely based on [Keep a Changelog](https://keepachangelog.com/); this
package is pre-1.0.

## [Unreleased]

### Changed (reaching the top, Android)

- The pinned bar turns on once the sheet's top is within 44 of the status
  bar (the list's first row within 68), either way, and plays out on its
  own 180 ms. The edge runs up to the status bar and the corners square
  with it, while the content keeps following the finger. It no longer
  needs the sheet fully raised.
- Docked, the first row stands 7 under the pinned bar (56): the sheet's
  top stands 39 under the status bar and its edge bleeds up to it
  (`AttachSheetPolicy.topBleed`, `pinnedWithin`). The dock zone is
  measured from the status bar, and the fast scroll's inset follows.

### Added (the dock at the top, Android)

- A sheet whose edge is left within 56 (the action bar's height) of the
  top, once its drag and fling are over, docks at the top by itself, as
  the list's smooth scroll: 300 ms and 300 more per viewport moved (at
  most 2000), easing out on a quintic. The edge drawn counts (a header's
  growth). `AttachSheetPolicy.dockMotion`, and `pinSnapZone` 56 on
  Android.
- `grabberCover` and `topExtension` take effect on the next frame even in
  an idle app.
- The Gallery's fast scroll starts its track under the bar pinned at the
  sheet's top: its thumb and date label no longer slide under it.

### Changed (the sheet's rest and the keyboard, Android)

- The resting top is taken over the window's whole height: the first row
  at 2/5 of it (1/3.5 in landscape) plus 4 under the status bar, the
  sheet's edge 24 above it. The band over the grid is 24 with nothing
  selected, with the handle 10 below the edge.
- `AttachSheetPolicy.restRisesWithKeyboard`. On Android the caption's
  keyboard no longer takes the sheet to its top
  (`expandsOnCaptionFocus` is false). The rest is taken over the window
  above the keyboard, and a sheet resting there, or below it, follows the
  keyboard up frame by frame. As the keyboard goes the rest returns and
  the sheet stays where it is. A sheet above the raised rest stays too.
- The selected-items preview keeps clear of the bar at the bottom, as the
  grid does.
- The selection header's band grows upward: the sheet's edge rises 26 as
  the words come and the grid under it holds still
  (`AttachSheetController.topExtension`; never above the sheet's top).
  The words (16, medium) and the menu stand centred in the 50 band.

### Fixed (the page switch)

- Each page on a switch is a sheet of its own: the sheet's background
  stands under its content, moving and fading with it. The page coming in
  covers the one going out as it fades in, instead of showing through
  over it until it vanishes.
- `AttachPageScope.presence`: how present a page is on a switch (the one
  going out gone by 0.7 of the out phase, the one coming in with it). The
  Gallery's live camera preview fades by it.

### Added (the selection header, breaking)

- `AttachSelectionHeaderController`, the selection header's behaviour with
  no widgets: its state (`AttachSelectionHeaderValue`: nothing selected,
  "N selected" by kind, the preview, the pinned bar) from the selection and
  the sheet, and the preview toggle (`togglePreview`, `closePreview`,
  `handleBack`), which ignores a toggle while the grid and preview swap
  still moves (`switchSettled`). The panel owns one
  (`AttachSendController.header`); it replaces `previewingSelection`,
  `selectionPreviewAvailable` and `toggleSelectionPreview`.
- `AttachSheetPolicy.selectionHeader` (`AttachSelectionHeaderStyle`, with
  `copyWith`) holds the host's choices: whether the preview exists
  (`previewEnabled`), from how many picks (`previewFrom`), where it opens
  from (`previewEntries`: the header, the send button's count), whether
  the header shows the selection and where the album switcher stands, the
  close button in the pinned bar, and the motion. `android` is the
  default on Android; `switcherHeader` (the previous header) elsewhere.
- On Android:
  - with nothing selected the header is empty;
  - with a selection it reads "3 photos selected" (videos, media),
    rising into place as it fades in, with the menu growing in beside it;
  - from two picks an arrow follows the words, and a tap on the header
    opens the selected-items preview under "Message preview", and a tap
    goes back;
  - the send button's count only sends;
  - the album switcher stands in the bar pinned at the sheet's top, after
    a close button and before the menu, and fades out while the preview
    shows;
  - the close button goes back from the preview first.
- `GalleryPage.create(headerBuilder:, pinnedItemsBuilder:,
  previewBuilder:)` and `GalleryHeaderParts`: a host's own header, pinned
  items and preview over the same behaviour. The stock skins are
  `AttachSelectionHeader`, `AttachPinnedItems` and `AttachPinnedBar`.
- `AttachSheetController.pinned`: the pinned bar's presence, 0 to 1.
- `AttachSheetController.grabberCover`: a header's share over the grabber.
  The grabber fades by its complement, so on Android it fades out as "N
  selected" fades in over its line.

### Changed (device round 1)

- On Android, with nothing selected, the band between the sheet's top and
  the grid is the handle's 13. It grows by 26 as the selection header
  rises in, and the handle fades out as the words come. The handle stands
  in the middle of the 13 band, 4.5 below the sheet's top (it was 20).
- The grid stays mounted under the selected-items preview, hidden and
  still: back from the preview it is as it was, with its loaded pages and
  its scroll. The preview scrolls on its own controller sharing the
  sheet's drag.
- A drag anywhere on the preview, its empty area below the picks too,
  moves the sheet as on the grid.

### Changed (the pinned bar)

- On Android the pinned bar fades in over 180 ms on the platform's ease in
  and out (it was 380 ms ease out quint), and a part of the way takes its
  share of that time.

### Added (the capture flow)

- The capture surface shows the shots this open keeps: its strip's own
  cells, numbered by the selection (`shotOrder`, `shotSelection`; a tap
  toggles, `onShotToggle`), and its shots counter reads "3 PHOTOS",
  "2 VIDEOS" or "5 MEDIA" from the strings. A camera session's shots join
  the strip only once the viewer's add-photo keeps them, so the first shot
  opens the viewer with no change to the camera's layout; after that, and
  while the strip shows kept shots, each shot joins it as it lands. A tap
  on the counter opens the viewer over the shots and the album, at the
  newest.
- A recording's poster is kept in the capture cache as a still under a key
  of its own and is its thumbnail in the grid (`PickerCapture.thumbnail`);
  it goes with the recording. The shots after a recording land after it.
- Back from the camera's viewer (the first shot's, or the counter's)
  takes the camera session's shots back, however many: they leave the
  captures, the strip, the selection and the capture cache. Shots of an
  earlier camera session stay. Only add-photo keeps them.
- The camera viewer's caption leads with add-photo while the keyboard is
  down (the panel button takes its place with the field focused or the
  panel up). A tap goes back to the camera and keeps the shot; a tap while
  the caption is open does nothing. There is no add-photo when one item is
  all the selection takes.
- `AttachCaptionBar.addMore`.

### Fixed (input guards)

- A tab switch is one motion until the new page rests: taps on tabs wait
  through its spring too, not only the out phase. The tab bar no longer
  drops with the sheet's switch drop (`AttachSheetController.jumpTop`
  takes `movesBar`).
- Send sends once per open: a spammed Send, or the send menu after it,
  does nothing more (`AttachSendController.send` answers false).

### Fixed (selection drag raises the sheet)

- A swipe selection held at the grid's bottom edge raises the sheet to its
  top first, then scrolls the grid, as a scroll of the page does. Held at
  the top edge it scrolls the grid back to its start and never moves the
  sheet: a drag while the page holds its own scroll (its physics turn user
  scrolling off) never lowers the sheet, and a selection's end leaves the
  sheet where it is. The grid's auto-scroll is a drag of the page, which
  the sheet's scroll position shares. A finger's drag back past the start
  still lowers the sheet. A jump (an album change, a fast scroll) only
  moves the page.

### Changed (the camera per platform)

- The capture surface takes the platform's policy
  (`CaptureSurfacePolicy.forPlatform` of the theme's platform): Android's
  as before, iOS's modes, lenses and results strip, with the mode names
  from `AttachStrings`.
- A shot removed from the results strip leaves the picker's captures and
  the selection, and its bytes are released; its tile is the capture's
  picture as the grid draws it.
- On the iOS sheet the grid's policy is `LibraryGridPolicy.$IOS`, so the
  viewer also opens on every 10th capture.

### Added (video refusals)

- `AttachInteraction.videoRefused(AttachVideoRefusal)`: a hold on the
  capture surface where only photos may be sent (`notAllowed`; the surface
  takes the kinds the limits allow), or whose microphone was refused
  (`microphone`; the surface asks for it first and records nothing). The
  host gives the bulletin.

### Changed (camera captures, breaking)

- `GalleryCamera.cache` (a `CaptureCache`, required): each shot moves into
  the host's bytes store under a `MediaKey.local`. The shots of an open are
  the picker's captures (`LibraryPicker.captures`): ahead of the library in
  the grid and the viewer, the first opening the viewer on it. Each joins
  the attach selection last, as `AttachSource.captured` of its key's stable
  form (it joined first, by its file path, before). A capture the selection
  refuses stays in the grid and the refusal goes to the host. The sheet
  going without a send releases its captures from the cache
  (`AttachSendController.sent` says what was sent).
- The grid's selection checks a capture by its local key.
- `AttachPreparation.capturedFile` (and `withPreparer(captures:)`) leases a
  capture's file from the cache to prepare it; a capture with no file is
  left out.
- A system camera capture is an `AttachSource.file` of its path.

### Changed (per-item captions)

- The sheet's caption field is the selection's shared caption, both ways:
  a reorder that hands the first item's caption on (Android) loads it.
  Sends carry each item's own caption (`AttachSelection.itemsToSend`).
- The picker viewer's caption is the shown item's: the field has its own
  text, loaded from `AttachSelection.captionOf` as the page changes and
  written through `setCaptionOf` (on Android typing on an item not
  selected selects it; on iOS a set sheet caption is every item's).

### Changed (fast scroll target)

- The gallery's fast scroll drives its grid through
  `ScrollControllerFastScrollTarget`, its month labels looked up at the
  offset of the progress asked; nothing changes on screen.

### Changed (tab press and switch, breaking)

- A held tab ripples instead of a flat wash: `AttachTabStyle.ripple`
  (`AttachTabRipple`: from 0.3 of the tab's longer side at the finger, it
  grows over 225 ms on `Cubic(0.4, 0, 0.2, 1)` to the tab's corners from its
  centre, fades in over 75 ms and, once lifted and grown, out over 150 ms),
  clipped to the tab's stadium. It replaces `pressFade`.
- The Android tab switch is the reference's: for 180 ms the sheet (its
  top, with both pages in it) moves toward the new page's top and drops 78
  while the new page fades in over the old (it paints above it); the old
  one goes and the sheet springs up to the new page's top. Before, the
  pages moved inside a sheet that held still and only then settled.
  `AttachSheetController` gains `topOf(expanded:)` and `jumpTop`. Before, the
  old page faded out alone and the new one faded in on the spring.

### Changed (sampled glass)

- The sheet is a glass source: its background and page (or the card) are
  the `GlassSource` of a `GlassSourceScope` around the sheet, and the bars
  over it, outside the source, sample it instead of filtering the scene on
  every frame. The caption island samples too, so it no longer shows
  see-through while the panel reveals under its fade. The gallery's fast
  scroll label, inside the page, samples a scope of its own around the
  grid. `AttachSheetHost.samplesGlass` (on by default) turns it off.

### Changed (tab bar, breaking)

- The Android tab bar is the reference's: a `GlassMaterial.tabs` stadium 56
  tall, 7 from the sides and above the bottom inset (was a 70 pill 11 from
  the sides); tabs 48 tall 4 inside it, clipped to the stadium; a 24 icon 4
  from the tab's top and an 11 label from 28.33, medium, extra bold when
  shown (measured at 12 for the tab's width, in whole pixels); the shown
  tab in `AttachTokens.tabSelected` on a 9 % stadium that grows from 0.6
  and fades in over 320 ms (decelerate) while the old one shrinks away,
  the others in `tabUnselected`; a held tab washed in `tabPressed`. It drops
  44 (was 36) while the sheet is at its top.
- The bar fades by its glass's own opacity (`GlassSurface.opacity`), the
  tabs and the iOS lens with it, so its glass reads the scene on every
  frame of a show or hide; before, an opacity layer over it left the glass
  see-through until the fade ended.
- `AttachTabBarStyle` gains `bottomPadding`, `pinnedDrop`, `glass`,
  `glassColors`, `colors` (an `AttachTabColorsOf`, by default
  `AttachTabColors.fromTokens`), `tab` (`AttachTabStyle`: icon and label
  layout, weights, the select motion, the `AttachTabIndicator` mark, the
  press wash) and `copyWith`. `height` is the glass's height and
  `innerPadding` the space between the glass and the tabs.
- `AttachPage.selectedIcon`: the tab's icon while its page is shown.
- The main button's sides line up with the tabs'.

### Changed (caption dock)

- The caption's panel is the host's: `AttachSheetHost.createCaptionDock`
  returns an `AttachCaptionDock` (the keyboard's place under the bar, the
  panel that can take it, the swap, back), replacing `buildCaptionPanel`.
  A bar on a dock stands at the bottom (`AttachSheet.bottomBarHoldsKeyboard`)
  and pads what the dock's place leaves; with no dock it stands on the safe
  area and the keyboard's inset. The sheet's own caption panel code
  (`AttachCaptionPanelSlot`, the toggle, the keyboard-height tracking) is
  gone.

### Changed (caption bar)

- The caption is the chat's composer island (`ComposerView` with the
  caption hint and limit) floating over the page in the composer's fade,
  with Send beside it, in the sheet, the viewer and the confirm box.

### Fixed (text style)

- The send menu, the overflow menu, the discard question, the gallery as
  files and the confirm box routes put a `ChromeTextRoot` at their root;
  every text style starts from `ChromeTypography`.

### Added (selected-items preview, library video)

- A tap on the panel's count swaps the Gallery's grid for the selected-items
  preview (`PickerSelectionPreview`): the picks in their order, a tap on a
  number deselects, a tap on a picture opens the viewer over the picks, a
  long press drags a pick to another place in the order (files and captures
  keep theirs). The count again, back, or an empty selection returns to the
  grid. `AttachSendController.previewingSelection`,
  `toggleSelectionPreview`; `AttachPickerSelection.move`.
- `GalleryPage.create(players:)` / `GalleryView.players`: the viewer's
  videos play on the host's players.

### Added (fast scroll)

- The Gallery grid has a fast scroll thumb with the month of the items in
  view beside it (`viewport_scroll`'s `FastScrollbar`): on Android it shows
  while the sheet is at its top over more than 30 items, on iOS while the
  grid scrolls. `AttachSheetPolicy.libraryFastScroll` and
  `libraryFastScrollMinCount` set it; `AttachStrings.libraryMonth` names
  the month.

### Fixed

- Text in the sheet, its pages, the panel and the confirm box takes the
  chrome face instead of the framework's underlined debug style: the sheet
  is a `ChromeSheetRoute` opened by its content, and the box's page has a
  `ChromeSheetRoot`.

### Added

- `AttachSheet` and `AttachSheet.show`: the mobile container with its scrim,
  resting height, open and close, a drag shared with the page's scroll
  (expand, pin, fling, snap, pull to dismiss), the discard guard, tap above
  to dismiss and the keyboard hand-off; `AttachSheetController` for the
  content below it.
- `AttachSheetPolicy` with the `$Android` and `$IOS` families: geometry,
  springs and timings, the release rule as a pure function, the iOS card on
  a wide screen.
- `AttachSheetHost`, `AttachSheetOpening`, `AttachDiscardQuestion`,
  `AttachOutcome.cancelled`.
- The page contract: `AttachPage`, `AttachPageId` (stock `gallery` and
  `files`), `AttachPageKind`, `AttachPagePermission`, `AttachMainButton`,
  `AttachPageRegistry` and the `AttachPageScope` hooks; `AttachSheet.show`
  takes the pages, keeps each one built for the open and switches them by
  the policy's motion; `AttachSheet.showContent` hosts any content.
- The tab bar per policy (`AttachTabBarStyle`, `AttachTabPopIn`,
  `AttachTabSwitch`): widths, pop-in, edge fade, auto-scroll, permission
  badge, hiding while the selection is not empty, a single tab collapsing it,
  a host page's main button in its place.
- `AttachOutcome.custom(page, payload)`; `AttachSheetController.restTop`,
  `dismissGuard` and `createScrollController`.
- iOS grows the sheet (or the wide-screen card) out of the attach button and
  back into it (`AttachSheetPolicy.morph`, `AttachSheetMorph`) when the host
  passes the button's rect; the tab bars are glass, and iOS marks the shown
  tab with a glass lens that slides and follows a drag (`AttachTabLens`).
- The fling the sheet carries between its rest and its top is
  `viewport_scroll`'s spline fling.
- The attach panel (`AttachSendController`, `AttachCaptionBar`,
  `AttachSendButton`, `AttachPanelReveal`, `AttachOverflowButton`,
  `AttachMenu`, `AttachPanelStyle`): the caption moved from the composer and
  returned on cancel, the counter send button with its bounce, the per-policy
  counter and over-limit refusal, the send menu and overflow entries over the
  model's visibility rules, the send option store read on open and written on
  send, and the swap with the tab bar.
- `AttachOutcome.send(request)`; `AttachOutcome.cancelled` carries the
  caption. `AttachSheetHost.interaction`, `pickSchedule`,
  `openExternalPicker`; `AttachInteraction`; `AttachPageScope.panel`;
  `AttachSheetController.maybeOf`.
- The Gallery page (`GalleryPage`, `GalleryView`, `AttachPickerSelection`)
  on `mpx_ui`'s library grid, the Files page (`FilesPage`,
  `RecentFilesSource`, `IntakeItems`) on `mpx_library`'s intake, and the
  desktop and web confirm box (`ConfirmBox`, `ConfirmBoxController`) with
  `AttachDropOverlay`; `AttachSheetPolicy.$Desktop` and `$Web`
  (`ConfirmBoxStyle`, `ConfirmBoxReorder`), `AttachSheetPolicy.libraryGrid`.
- `AttachSheetHost.pickTimer`; send menu entries for high quality and
  spoiler; Send opens its menu on a right click too.
