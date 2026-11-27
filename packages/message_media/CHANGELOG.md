# Changelog

All notable changes to `message_media` are documented in this file. The
format is loosely based on [Keep a Changelog](https://keepachangelog.com/);
this package is pre-1.0.

## [Unreleased]

### Added

- Gestures: `MessageMediaView` (and `MessageMediaTransition`) take
  `selection`, `messageId`, `onOpenViewer` and `onItemMenu`; with a
  facade the view registers as the message's non-text body and answers
  body part hits for the content, the status control, a hidden spoiler
  and the options affordance. `MediaGesturePolicy` (`android()`, `ios()`,
  `desktop()`; `MessageMediaPolicy.gestures`) says what a tap does
  (`MediaPartAction`, `MediaLoadingTap`), the cursor, the hover highlight
  (`MediaHoverLook`) and the input guard. `MediaViewerRequest` and
  `MessageMediaState.rectOf` give the viewer its origin frames.
- Semantics: one node per item, worded by `MediaSemanticsStrings`
  (`MessageMediaPolicy.semantics`).
- `MediaItemAction.allowedItemActions`, the per-item actions an item
  allows under the chat's protection; `message_media` now depends on
  `chat_capabilities` for `ChatProtection`.
- `MediaBoxCell.presetFor`, `MediaRowCell.presetOf` and `rowOf`.
- `media` / `hit`, `activationDropped`, `viewerOpened` and
  `originRectMissing` diagnostics.

- Chrome slots (`MessageMediaPolicy.chrome`, `MediaChromeSlots` with
  `android()`, `ios()`, `desktop()`): the time pill's rect
  (`MediaTimePillPlacement`, reported as `MediaLayout.timePill` when the
  time sits on the media), the info badge and status control over the
  stock parts, the spoiler cover (`MediaSpoilerCover`, `MediaSpoilerLook`)
  with its reveal (`MediaSpoilerReveal`: `circle`, `spot`, `crossFade`),
  and the options affordance (`MediaOptionsPlacement`,
  `MediaOptionsAffordance`, `MediaOptionsDots`, `MediaChromeContext`).
  `MessageMediaView` takes `chromeContext` and `selectionProgress`.
  `MessageMediaPolicy`'s main constructor now requires `chrome`.
- `MessageMediaState.revealSpoiler(id, at:)` and `takeRevealOrigin`;
  `MessageMediaStateBuilder.scrollId` is optional.
- `MediaLayoutChrome.timeHeight`, `MediaLayout.withTimePill`,
  `MediaCellData.chrome` and `.correlation`, `MediaBoxCell.skin` and
  `skinOf`.
- `media` / `spoilerRevealed` diagnostics; `cellFailed` also names a
  failed chrome slot.

- `IosMosaicAlgorithm`, the iOS family's mosaic, now the
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
- `MediaFitPolicy.album`: the fit of every box in a mosaic of two or more,
  `crop` on every platform. An album box's size follows the mosaic, not its
  picture, so it fills. Existing albums on iOS (photos were `blurFit`) and
  desktop (`cropIfVisible`) now crop each box; a box laid out alone keeps
  its kind's fit.

- Layout transitions. `MediaLayout.lerp` interpolates two layouts by
  item (rect, corner radii, block rects, size, time pill, caption wrap
  width; fit and kind snap); the cells that left are in
  `MediaLayout.exiting` until their exit ends. `MediaTransitionPolicy`
  (`android()`, `ios()`, `desktop()`, `none()`) holds each platform's
  move, exit and enter timings, and `MessageMediaPolicy.transition`
  carries it. `MessageMediaTransition` is the per-message clock
  (`MediaLayoutTransition` legs, `MediaTransitionFrame` with
  `MediaCellFade`s), continuing from the current frame when the layout
  changes mid-flight and jumping to the end under reduce motion.
  `MessageMediaView` takes `fades` and paints the exiting cells.
- `media` / `transitionStarted` and `transitionInterrupted` diagnostics,
  and the package's timeline sections `media.layout`, `media.lerp` and
  `media.cellBuild`.
- `DesktopMosaicAlgorithm` (`name` `desktop`; `maxWidth` 430, `minWidth`
  100, `spacing` 4), the desktop policy's album layout: fixed forms for two
  to four items, lines for five or more or a very wide item, laid out at
  430 and scaled down to the block width. `MediaCornerPolicy.desktop()`
  squares the corners between boxes (`item` 0, was the interim 4); the
  desktop album goldens changed with it.
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

- The status control of a box and of a row takes no pointer: its taps are
  the view's body part hits, so a tap on it toggles the message in
  selection instead of downloading.

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
