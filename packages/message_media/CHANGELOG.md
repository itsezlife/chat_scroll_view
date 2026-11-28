# Changelog

All notable changes to `message_media` are documented in this file. The
format is loosely based on [Keep a Changelog](https://keepachangelog.com/);
this package is pre-1.0.

## 0.1.0 (unreleased)

The first release ([ADR 047](../../docs/adr/047-message-media.md)). It lays
a message's media items out, draws them, answers taps on them and animates
their changes.

### The policy and the layout

- `MessageMediaPolicy` (`android()`, `ios()`, `desktop()`, `web()`,
  `platform()`, `forPlatform`), each part replaceable through `copyWith`: the layout step
  (`MediaLayoutStep`, the default `MediaLayoutPolicy`), the file rows
  (`fileStack`) and the link preview card (`linkPreview`), which every step
  is handed and the cells draw by, the corners (`MediaCornerPolicy`), the
  autoplay flag (`MediaAutoplayPolicy`), the cell builders
  (`MediaCellBuilders`), the chrome slots (`MediaChromeSlots`), the layout
  transition (`MediaTransitionPolicy`), the send flight
  (`MediaSendFlightPolicy`) and the gestures (`MediaGesturePolicy`).
- `MediaLayoutPolicy` lays boxes (pictures: photo, video, animation) into
  mosaic blocks, files and custom kinds into file stacks and the link
  preview into a card block last. Its parts: `MediaBoxSizing` (`$Android`,
  `$IOS`, `$Desktop`, `$Web`), the `MosaicAlgorithm` slot (`GroupedMosaicAlgorithm`,
  `IosMosaicAlgorithm`, `DesktopMosaicAlgorithm`), `MediaFitPolicy` (per
  kind alone, `album` for a mosaic) and `MediaCaptionWidthPolicy`.
- `MediaLayoutInput` (with `MediaLayoutChrome`, `MediaLinkPreviewInput`,
  `MediaCaptionPosition`) in, `MediaLayout` out: `MediaBlock`s (`mosaic`,
  `fileStack`, `linkPreview`) of `MediaCell`s keyed by `MediaItemId`, each
  with a rect, a `MediaFit`, its `MediaNeighbours` and the corner radii
  `MediaCornerPolicy` resolves, plus the caption's `MediaWidthMetrics` and
  the time pill's rect.
- `MediaLayoutText`, the input's text: one base style (the chrome
  typography), one text scaler (the platform's), the host's media strings
  (`ChromeStringsScope.mediaOf`) and the `MediaTextMeasure`. The layout
  measures with it and the cells paint with the same, so a themed family or
  a larger text size lays out the lines it draws. Hosts build it with
  `MediaLayoutText.of(context)`.
- The geometry under the default layout: `SingleMediaLayout.compute`,
  `GroupedMessages.calculate` (`GroupedMediaMember`,
  `GroupedMessagePosition`, `GroupedPositionFlags`), `MosaicLayout.project`
  (`MosaicCellLayout`) and `MediaLayoutMetrics`.
- The file stack, `MediaFileStackPolicy`: rows in a vertical stack with each
  platform's bubble width, row metrics with and without a thumbnail, name
  lines, pull-ups, the time's growth and the desktop footer line; each file
  keeps a caption slot of its own (`MediaLayoutInput.fileCaptionHeights`).
  `MediaFileRow` per row, type from `MediaFileText`.
- The link preview card, `LinkPreviewCardPolicy` with
  `LinkPreviewBlockStyle`, `LinkPreviewCardMetrics`, `LinkPreviewCardText`,
  `LinkPreviewCardWidth`, `LinkPreviewMediaSizeRule`,
  `LinkPreviewAppearForm`, `LinkPreviewCardPress`,
  `LinkPreviewEnlargeButton` and `LinkPreviewTimePlacement`; its media is an
  ordinary cell keyed by `MediaItemId.linkPreviewOf`.

### The paint

- `MessageMediaView` paints a layout with the policy's cell builders
  (`MediaBoxCell`, `MediaRowCell`) through `content_assets`'
  `ContentAssetView`, with the chrome slots over them: the time pill's rect,
  the info badge, the status control, the sent check, the spoiler
  (`MediaSpoilerCover`, `MediaSpoilerReveal`) and the options affordance.
- A file row cuts its name in the middle (`MiddleElidedText`), with the full
  name in the chrome tooltip on the desktop; its words come from the host's
  media strings.
- The card is drawn in `LinkPreviewCardColors`, the host's or the chrome
  palette's accent (`LinkPreviewCardColors.of`); the fill's share in a dark
  theme follows the palette's brightness.
- `MessageMediaBubbleLayout` (with `MediaBubbleComposition`) places the
  caption, the header, each file's caption and the time around the media by
  `invertMedia`.
- Every route and overlay the package shows roots in the chrome text style;
  every text starts from `ChromeTypography`.

### Gestures, semantics and state

- With a selection facade the view is the message's non-text body and
  answers body part hits (`MessageMediaHitPart`: `MediaHitPart`,
  `LinkPreviewHitPart`) for the content, the status control, a hidden
  spoiler, the options affordance and the card. A card of a view with no
  message id is no part. `MediaGesturePolicy` says what a tap does, the
  cursor, the hover highlight and the input guard; `MediaViewerRequest`
  and `MessageMediaState.rectOf` give a viewer its origin frames.
- The web (`MessageMediaPolicy.web()`, what `platform()` gives in a
  browser): boxes by the window's width class (`MediaLayoutInput.widthClass`,
  else its `displaySize`), 340 compact and 420 wider, re-laid out at once on
  a resize; the hover highlight and the click cursor only for a mouse-class
  pointer (`MediaGesturePolicy.web`, `hoverNeedsMouse`).
- One semantics node per item and one per card, worded by the host's media
  strings.
- `MediaItemAction.allowedItemActions`: the per-item actions an item allows
  under the chat's protection.
- `MessageMediaState`: what a chat's items remember while it is open (a
  revealed spoiler), the send origin and the mounted views' rects
  (`MediaItemRect`).
- Outgoing media: `MediaSendState`, uploads on the status control, the sent
  check, the cross that drops an item being sent (`onItemCancelled`) and
  the iOS flight from the send origin.
- `MediaLayout.lerp` and the per-message clock `MessageMediaTransition`
  animate a change of the layout, jumping to the end under reduce motion.

### Diagnostics

- `media` events (`MediaOp`): `layoutComputed`, `layoutFallback`,
  `unknownKind` (once per kind for each diagnostics sink), `cellFailed`
  (with the `MediaBuilder`), `spoilerRevealed`, `transitionStarted`,
  `transitionInterrupted`, `hit` (with the `MediaHitOutcome`),
  `activationDropped`, `viewerOpened`, `originRectMissing` (with the
  `MediaViewerMoment`), `uploadState`, `itemCancelled`,
  `sendOriginFlight` (with the `MediaFlightOutcome`) and `webClassChanged`;
  `linkPreview` /
  `cardShown`. Timeline sections `media.layout`, `media.lerp`,
  `media.cellBuild` and `media.cardLayout`.

### Dependencies

- The root `chat_scroll_view` (body part hits), `chat_capabilities`
  (protection), `chrome_foundation` (typography, palette, strings, tooltip,
  ink), `content_assets` and `mpx_core` (the cells' pictures and status
  control), `content_model` (media ids and kinds).
