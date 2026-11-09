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
- The desktop toast (ticket 132), its values checked against the toolkit
  `lib_ui`: `DesktopBulletinBuilders`, `BulletinMessage` and
  `Bulletin.links`; the policy's `minWidth`, `transitionAt` and
  `passesThroughWhenInert` (defaults keep the Android and iOS families as
  they were); `BulletinTransition.timedSlide` and explicit times on
  `fade`. `BulletinPolicy$Desktop` changes: margin 16 → 13, radius 9 → 8,
  padding 16 → 19 at the sides, width 380 → 160 to 360 as wide as its text,
  icon slot 32 → 44, minimum height 40 → 24, fade 200 ms in and 1000 ms
  out instead of the motion roles, a 160 ms slide when attached to an edge.
  A host switch over `BulletinTransition` adds the `timedSlide` case.
