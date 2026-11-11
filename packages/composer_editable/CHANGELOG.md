# Changelog

All notable changes to `composer_editable` are documented in this file. The
format is loosely based on [Keep a Changelog](https://keepachangelog.com/); this
package is pre-1.0.

## [Unreleased]

### Breaking

- The handle motion duration is `kHandleMotionDuration`; the former constant
  named after another client is gone.
- The magnifier's settle rate is `kMagnifierSettleMs`, named by its role; the
  per-axis aliases are `kMagnifierXSettleMs` and `kMagnifierYSettleMs`. The
  former constants are gone (the per-axis ones were internal and never
  exported).
- Local names in `text_selection.dart` changed to `focalY` and
  `magnifierCaretRect`; they are not API.
