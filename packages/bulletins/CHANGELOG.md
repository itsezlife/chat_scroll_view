# Changelog

All notable changes to `bulletins` are documented in this file. The format is
loosely based on [Keep a Changelog](https://keepachangelog.com/); this package
is pre-1.0.

## [Unreleased]

### Fixed (a toast with a leading keeps its text's height)

- `BulletinLeadingSlot` is as tall as its content: a card whose height is not fixed (the desktop toast) no longer grows to the surface's height when it has a leading.
- The desktop toast's leading sits with 2 px above and below and never makes the toast taller than its text and padding.

### Breaking

- No API change here. The doc comments and tests now name the `chrome_foundation` tokens `BulletinTokens.desktop` and `BulletinTokens.android` (was `referenceDesktop` and `referenceAndroid`). See the `chrome_foundation` changelog.

### Added

- The package ([ADR 045](../../docs/adr/045-bulletins.md)): the `Bulletin`
  value with its leading kinds, actions and duration classes;
  `BulletinController` with one slot per surface, the timer from the enter,
  pause and resume, and commit on leave for Undo bulletins; `BulletinHost`
  with the obstruction seam, the enter and exit, press and swipe, and the
  announcement; `BulletinPolicy` with the Android, iOS and desktop families;
  `BulletinBuilders` with flat stock builders; `ManualBulletinClock` and
  `BulletinPolicyContract` in `testing.dart`.
- The desktop toast (ticket 132), its values checked against the desktop
  toast style: `DesktopBulletinBuilders`, `BulletinMessage` and
  `Bulletin.links`; the policy's `minWidth`, `transitionAt` and
  `passesThroughWhenInert` (defaults keep the Android and iOS families as
  they were); `BulletinTransition.timedSlide` and explicit times on
  `fade`. `BulletinPolicy$Desktop` changes: margin 16 → 13, radius 9 → 8,
  padding 16 → 19 at the sides, width 380 → 160 to 360 as wide as its text,
  icon slot 32 → 44, minimum height 40 → 24, fade 200 ms in and 1000 ms
  out instead of the motion roles, a 160 ms slide when attached to an edge.
  A host switch over `BulletinTransition` adds the `timedSlide` case.
- The iOS presentation: `BulletinIOS.builders()` (blurred card, leading slot,
  multi-line text, the 17 action label) and `BulletinCountdownIOS`;
  `BulletinPolicy$IOS` takes `sideInset`, `bottomInset`, `elevated` and
  `narrow`.
- `BulletinTransition.fadeScale` takes `enter` and `exit`
  (`BulletinFadeScaleMotion`) to time the fade and the scale apart. A host
  that compared `BulletinPolicy.ios().transition` to a plain
  `fadeScale()` sees them differ now.
- The Android card (ticket 130): `BulletinBuilders$Android` (the opaque
  undo card, or glass in a chat; the 56 x 48 leading slot, the 29
  thumbnail, the 20 countdown ring with sliding digits; Undo and buttons
  with a pressed highlight; the text sizes and line counts of the card) and
  `BulletinCountdown$Android`. `BulletinPolicy$Android` changes: margin 8 →
  16 at the sides, leading slot 48 → 56. The host now slides a spring card
  by its height and both vertical margins, flings it on a stiffness-100
  spring, swipes only once entered, fades a drag where the card is narrower
  than its area, and scales only a card with a body tap (80 ms in, 350 ms
  overshoot out).

### Changed

- `BulletinPolicy.ios()` now uses 12 from every edge (was 8
  above and below), leading slot 50 from the card's edge (was 38 after the
  padding), icon 32 (was 28), `passesThroughWhenInert` true (an overlay with
  nothing to press lets touches through), and its own fade and scale timing
  instead of the shared motion roles.
