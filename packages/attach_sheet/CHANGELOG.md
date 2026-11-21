# Changelog

All notable changes to `attach_sheet` are documented in this file. The format
is loosely based on [Keep a Changelog](https://keepachangelog.com/); this
package is pre-1.0.

## [Unreleased]

### Added (the capture flow)

- The capture surface shows the shots this open keeps: its strip draws each
  as the grid's cell, with its check and order number (a tap toggles it),
  and its shots counter reads "3 PHOTOS", "2 VIDEOS" or "5 MEDIA" from the
  strings. A tap on the counter opens the viewer over the shots, at the
  newest.
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
