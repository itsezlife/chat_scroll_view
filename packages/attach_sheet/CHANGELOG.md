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
