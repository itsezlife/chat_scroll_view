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
