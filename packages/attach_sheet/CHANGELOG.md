# Changelog

All notable changes to `attach_sheet` are documented in this file. The format
is loosely based on [Keep a Changelog](https://keepachangelog.com/); this
package is pre-1.0.

## [Unreleased]

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
