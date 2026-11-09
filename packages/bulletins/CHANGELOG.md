# Changelog

All notable changes to `bulletins` are documented in this file. The format is
loosely based on [Keep a Changelog](https://keepachangelog.com/); this package
is pre-1.0.

## [Unreleased]

### Added

- The package ([ADR 045](../../docs/adr/045-bulletins.md)): the `Bulletin`
  value with its leading kinds, actions and duration classes;
  `BulletinController` with one slot per surface, the timer from the enter,
  pause and resume, and commit on leave for Undo bulletins; `BulletinHost`
  with the obstruction seam, the enter and exit, press and swipe, and the
  announcement; `BulletinPolicy` with the Android, iOS and desktop families;
  `BulletinBuilders` with flat stock builders; `ManualBulletinClock` and
  `BulletinPolicyContract` in `testing.dart`.
- The iOS presentation: `BulletinIOS.builders()` (blurred card, leading slot,
  multi-line text, the 17 action label) and `BulletinCountdownIOS`;
  `BulletinPolicy$IOS` takes `sideInset`, `bottomInset`, `elevated` and
  `narrow`.
- `BulletinTransition.fadeScale` takes `enter` and `exit`
  (`BulletinFadeScaleMotion`) to time the fade and the scale apart. A host
  that compared `BulletinPolicy.ios().transition` to a plain
  `fadeScale()` sees them differ now.

### Changed

- `BulletinPolicy.ios()` follows the reference: 12 from every edge (was 8
  above and below), leading slot 50 from the card's edge (was 38 after the
  padding), icon 32 (was 28), and its own fade and scale timing instead of
  the shared motion roles.
