# Changelog

All notable changes to `swipe_pager` are documented in this file. The format
is loosely based on [Keep a Changelog](https://keepachangelog.com/); this
package is pre-1.0.

## [Unreleased]

### Added

- `SwipePager`, a horizontal pager whose swipe is claimed past a slop and a
  direction rule (`SwipePagerPhysics`), so a page's vertical scrollables and
  nested horizontal scrollers keep their drags.
- `SwipePagerController`: `page`, `position`, `animateTo`, `jumpTo`, typed
  page and position listeners.
- `SwipePagerKeepAlive`: `all`, `none` and `recent(n)`.

### Changed

- A nested horizontal scroller at its edge in the drag's direction no longer
  keeps the drag to overscroll: the pager takes it and swipes under its usual
  slop and direction rule. A scroller that can scroll that way keeps the drag
  as before. The pager now routes its own pointers instead of through a
  `RawGestureDetector`, and reads the platform drag slop from `MediaQuery`.
