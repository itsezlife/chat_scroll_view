# Changelog

All notable changes to `composer_editable` are documented in this file. The
format is loosely based on [Keep a Changelog](https://keepachangelog.com/); this
package is pre-1.0.

## [Unreleased]

### Breaking

- `kTelegramHandleMotionDuration` is `kHandleMotionDuration`.
- `kTelegramMagnifierXSettleMs` is `kMagnifierXSettleMs`, and `kTelegramMagnifierYSettleMs` is `kMagnifierYSettleMs`. Both are internal and were never exported. `kAospMagnifierSettleMs` is unchanged; it names the platform default.
- The local names in `text_selection.dart` changed (`telegramFocalY` is `focalY`, `telegramCaretRect` is `magnifierCaretRect`); they are not API.
