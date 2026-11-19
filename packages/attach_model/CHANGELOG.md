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
- `planSend`: the pure send plan with each family's grouping and caption
  rules (groups of ten, form changes, timers and animations alone, the
  batch-wide breaks, the caption's place, a text caption ahead on the web)
  and typed rejections.
- `SendOptions`, `SendRequest`, `SendSchedule`; `SendOptionVisibility` for
  the options a menu or box shows; `SendOptionStore` over `KeyValueStore`
  with per-family persistence (desktop only on Remember, web never).
- `AttachPolicyContract` checks every plan sends each item once, in order,
  with one caption.
