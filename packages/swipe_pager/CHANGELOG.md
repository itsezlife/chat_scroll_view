# Changelog

All notable changes to `swipe_pager` are documented in this file. The format
is loosely based on [Keep a Changelog](https://keepachangelog.com/); this
package is pre-1.0.

## [Unreleased]

### Changed (an off-screen page says it is invisible)

- A page that is not on screen is under an invisible `Visibility` that keeps
  its state, in place of bare `Offstage` and `TickerMode`: still offstage,
  out of focus and with its tickers off, and `Visibility.of` is now false in
  it. Content that reads it (a catalogue) gives back what it plays on while
  the page is away. A page sliding in is visible from its first step.

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
