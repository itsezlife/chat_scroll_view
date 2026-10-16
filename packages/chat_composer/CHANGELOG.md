# Changelog

All notable changes to `chat_composer` are documented in this file. The format
is loosely based on [Keep a Changelog](https://keepachangelog.com/); this package
is pre-1.0.

## [Unreleased]

### Added

- `ComposerController`: input-only controller (text, focus, selection, field
  scroll and height, `SoftKeyboardMode`, commands `insertText`, `insertContent`,
  `backspace`, `clear`, `restore`).
- `ComposerTextController`: a `TextEditingController` that keeps `RichText`
  entities in step with edits, treats inline content and mentions as atomic,
  and applies IME compositions as one replacement when they finish.
- `ComposerInputQuery` observable with host-registered `ComposerQueryKind`s
  and `ComposerController.replaceQuery`.
