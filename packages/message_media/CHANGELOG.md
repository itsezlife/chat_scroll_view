# Changelog

All notable changes to `message_media` are documented in this file. The
format is loosely based on [Keep a Changelog](https://keepachangelog.com/);
this package is pre-1.0.

## [Unreleased]

### Added

- `MessageMediaHitPart`, the sealed part id message media puts in a body
  part hit: `MediaHitPart(itemId, part: MediaPart)` and
  `LinkPreviewHitPart(messageId, zone: LinkPreviewZone)`, each with its
  `ChatBodyPartRole` (only `MediaPart.options` opens the menu) and its
  diagnostics name. The package now depends on the root `chat_scroll_view`.
- The package ([ADR 047](../../docs/adr/047-message-media.md)) with the
  default media layout's geometry: `computeSingleMediaSize`,
  `GroupedMessages.calculate` with `GroupedMediaMember`,
  `GroupedMessagePosition` and `GroupedPositionFlags`, `MosaicLayout` with
  `MosaicCellLayout`, and `MediaLayoutMetrics`.
- Cells are addressed by `MediaItemId`: a member carries its item's `id`,
  `GroupedMessages.positionOf(id)` and `MosaicLayout.cellOf(id)` find a
  cell, and the caption owner is `captionItemId`. Kinds are
  `content_model`'s `MediaItemKind`; only photo, video and animation are
  boxes.
- `MessageMediaPolicy` (`android()`, `ios()`, `desktop()`, `platform()`,
  `forPlatform`) with a replaceable `MediaLayoutStep`; the default
  `MediaLayoutPolicy` with `MediaBoxSizing` (`$Android`, `$IOS`,
  `$Desktop`), the `MosaicAlgorithm` slot (`GroupedMosaicAlgorithm`) and
  `MediaFitPolicy`, each part replaceable through `copyWith`.
- `MediaLayout`: `MediaBlock` (`mosaic`, `fileStack`, `linkPreview`) of
  `MediaCell`s keyed by item, each with a rect, a `MediaFit` and
  `MediaNeighbours`; slots for the caption's `MediaWidthMetrics` and the
  time pill's rect. Inputs: `MediaLayoutInput`, `MediaLayoutChrome`,
  `MediaLinkPreviewInput`, `MediaCaptionPosition`.
- `media` diagnostics (`MediaOp`): `layoutComputed`, `layoutFallback`,
  `unknownKind`.

### Changed

- `computeSingleMediaSize` gives a side that truncates to zero 150, not
  120: 150 is the Android box without dimensions. It takes an explicit
  `maxHeight` (not soft-capped), `minHeight` and `zeroSide`, so a policy
  passes its own values.
- `MosaicLayout.project` takes `rowHeightUnit`, the pixel height of a full
  row; the Android album passes half of `max(list width, screen height)`.
  Without it the rows keep the mosaic's own proportions, as before.
