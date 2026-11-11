# Changelog

All notable changes to `composer_editable` are documented in this file. The
format is loosely based on [Keep a Changelog](https://keepachangelog.com/); this
package is pre-1.0.

## [Unreleased]

### Added (the text actions query, once for every field)

- `ProcessTextQueryCache`: a binary messenger over the platform's that answers the text processing actions query from its first reply, for every text field of the app, stock `EditableText`s included (they query on every mount, on the UI thread on Android). Queries in flight together share one call; a failed call is asked again; every other message passes through. A host installs it as its binding's messenger.

### Breaking

- The handle motion duration is `kHandleMotionDuration`; the former constant
  named after another client is gone.
- The magnifier's settle rate is `kMagnifierSettleMs`, named by its role; the
  per-axis aliases are `kMagnifierXSettleMs` and `kMagnifierYSettleMs`. The
  former constants are gone (the per-axis ones were internal and never
  exported).
- Local names in `text_selection.dart` changed to `focalY` and
  `magnifierCaretRect`; they are not API.
