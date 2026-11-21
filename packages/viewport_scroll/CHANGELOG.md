# Changelog

All notable changes to `viewport_scroll` are documented in this file. The
format is loosely based on [Keep a Changelog](https://keepachangelog.com/);
this package is pre-1.0.

## [Unreleased]

### Changed (thumb drag slop)

- `FastScrollbarPolicy.dragSlop`: how far a press on the thumb moves
  before the drag starts. `$Android` takes 8, the platform's touch slop,
  in place of Flutter's 18, so the content follows almost at once and the
  thumb takes the drag ahead of the list; the move inside the slop is not
  lost. `$IOS` keeps the gesture settings' slop (it also starts on a hold).

### Changed (fast scrollbar on any engine, breaking)

- `FastScrollbar` drives a `FastScrollTarget` (`target:`) in place of a
  `ScrollController` (`controller:`). The target is fraction-based: where
  the content is (`progress`, 0 to 1, null when it cannot scroll), how
  much of it is in view (`visibleShare`), `jumpTo(progress)`, `stop()`, the
  drag brackets, and a change signal. Before / after:
  `FastScrollbar(controller: c)` becomes
  `FastScrollbar(target: ScrollControllerFastScrollTarget(c))`, with the
  same behaviour.
- `FastScrollLabeler` takes the progress, not the scroll offset. A host
  keyed by offset converts with `ScrollControllerFastScrollTarget.offsetAt`.

### Added

- `testing.dart`: `FakeFastScrollTarget` and `FastScrollTargetContract`.
