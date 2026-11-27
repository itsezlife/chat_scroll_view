# Changelog

All notable changes to `message_media` are documented in this file. The
format is loosely based on [Keep a Changelog](https://keepachangelog.com/);
this package is pre-1.0.

## [Unreleased]

### Added

- The file stack. `MediaFileStackPolicy` (`android()`, `ios()`,
  `desktop()`, `copyWith`) lays files out as rows in a vertical stack with
  each platform's bubble width, row metrics with and without a thumbnail,
  name lines, row pull-ups, the time's growth and the desktop footer line.
  `MediaBlock$FileStack` now carries a `MediaFileRow` per row (`rows`,
  `rowOf`) and its `footer`; `MediaLayoutInput.fileCaptionHeights` gives
  each file its own caption slot; `MediaLayoutChrome.hasFooterInfo` asks
  for the desktop footer line.
- `MediaRowCell` draws the row: control or thumbnail, the name cut in the
  middle (`MiddleElidedText`, `middleElide`), the info line with its
  progress, the desktop link line; desktop rows mirror in right-to-left
  lists. Words come from `MediaFileStrings` (English by default), type from
  `MediaFileText` over `ChromeTypography`; the package now depends on
  `chrome_foundation`. `MediaCellData` carries `fileRow` and `fileStack`.

### Changed

- `MediaLayoutPolicy.fileRowHeight` is replaced by `fileStack`. A file
  stack is no longer the box budget wide with fixed 56 / 65 / 60 rows: an
  Android stack of two is now `min(listWidth − 50, 300)` wide and its rows
  overlap, so code that asserted the interim rects sees the new ones.
  `MediaRowCell` takes a `row` and a `policy`.

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
