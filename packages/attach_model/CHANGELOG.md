# Changelog

All notable changes to `attach_model` are documented in this file. The format
is loosely based on [Keep a Changelog](https://keepachangelog.com/); this
package is pre-1.0.

## [Unreleased]

### Added

- The attach item (`AttachItem`, `AttachSource`, `AttachKind`, `AttachFacts`,
  `AttachTimer`) with the edited-item slot (`ItemEdits`, `DerivedOutput`)
  that the effective facts read.
- `AttachLimits`, the host's rights for one open.
- `AttachSelection`: ordered, capped per policy, gated by kind and file
  size, with range toggles, reorder that keeps per-item state, and snapshots
  for an undo. Refusals are values (`AttachToggle.refused`), never thrown.
- `AttachPolicy` with the `$Android`, `$IOS`, `$Desktop` and `$Web` families
  and `forPlatform`; the selection cap is 100 on mobile and none on desktop
  and web.
