# Changelog

All notable changes to `attach_sheet` are documented in this file. The format
is loosely based on [Keep a Changelog](https://keepachangelog.com/); this
package is pre-1.0.

## [Unreleased]

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
