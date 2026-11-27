# Changelog

All notable changes to `attach_model` are documented in this file. The format
is loosely based on [Keep a Changelog](https://keepachangelog.com/); this
package is pre-1.0.

## [Unreleased]

### Added (album size)

- `AttachLimits.albumSize` (default 10, at least 1), in `==`, `hashCode` and the new
  `copyWith`; the send plan groups at the smaller of the policy's `maxGroupSize`
  and `albumSize`.

### Changed

- `AttachLimits.captionLength` counts code points of the caption's plain text,
  as the message length budget does, not UTF-16 code units; the send plan
  checks the batch caption and each item's caption that way.

### Added (per-item captions, breaking)

- Each item can carry its own caption beside the shared one (the sheet's
  field), related by the new `AttachPolicy.itemCaptions` (`ItemCaptions`):
  - `firstItem` (Android): the shared caption is the first item's. While no
    other item has one, the viewer shows it on every item; a different
    text on another item gives that item its own. A caption typed on an
    unselected item selects it, deselecting clears it, and a reorder keeps
    each caption with its item.
  - `forced` (iOS): the shared caption, while set, is every item's; empty,
    each item keeps its own, selected or not.
  - `sharedOnly` (desktop, web): one caption.

  A policy that extends `AttachPolicy` directly must implement it.
- `AttachSelection.caption` (shared), `captionOf`, `setCaptionOf`,
  `ownCaptionOf`, `captionsPerItem`, `itemsToSend` (the items with their
  own captions on) and `captionChanges`, which caption edits signal in
  place of `changes`.
- `planSend` sends own captions: on a single item as its `caption`, in a
  group as `PlannedSend$Group.itemCaptions` (`captionOf(i)` gives an item's
  caption, batch or own). Under `firstItem` the first item takes the shared
  caption; under `forced` a set shared caption wins over every own one and
  is placed once. An own caption over the limit is `captionTooLong`.

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
