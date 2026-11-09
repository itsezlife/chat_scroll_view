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
