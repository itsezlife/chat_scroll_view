# Changelog

All notable changes to `message_media` are documented in this file. The
format is loosely based on [Keep a Changelog](https://keepachangelog.com/);
this package is pre-1.0.

## [Unreleased]

### Added

- `MosaicAlgorithm$IOS`, the iOS family's mosaic, now the
  `MediaLayoutPolicy.ios()` `mosaicAlgorithm`: a fixed pattern by
  orientation mix for two to four boxes, else the best split into two to
  four rows, within 300 × 380 on a compact list and 440 × 440 on a regular
  one (`maxSizeFor`), seams of 1. A pattern that would leave a box no area
  is laid in rows instead and reports `layoutFallback` with the new rule
  `MediaLayoutFallbackRule.mosaicRows`. iOS albums now lay out differently
  from the Android ones; a row-laid album can be up to a few pixels wider
  than the block width, as rows round each box up.
- `MediaCornerPolicy.ios()` rounds a corner between two boxes with 0 on a
  compact list and 5 on a regular one (was 4).

- The paint step's first part. `MediaCornerPolicy` (`android()`, `ios()`,
  `desktop()`) resolves each cell's numeric `MediaCornerRadii` from its
  neighbours, the joined bubble's side, the list's width class and the
  bubble's tail (`MediaTailRule`); `MessageMediaPolicy.layout` returns the
  cells with their radii (`MediaCell.radii`, `MediaLayout.mapCells`).
- `MessageMediaView` paints a `MediaLayout`, each cell keyed by its item,
  with the policy's `MediaCellBuilders` (`box`: `MediaBoxCell`, `row`:
  `MediaRowCell`), each replaceable on its own. Cells draw through
  `content_assets`' `ContentAssetView`; the package now depends on
  `content_assets` and `mpx_core`.
- `MediaFit.drawIn` and `MediaFitDraw`: a box crops, or draws the whole
  picture over bars blurred from the same cache entry.
- `MediaAutoplayPolicy` (`android()`, `ios()`, `desktop()`, `off`): which
  videos and animations play inline, muted.
- `media` / `cellFailed` diagnostics.

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
