# message_media

Message media display. A **message media policy** lays a message's **media
items** out into a **media layout**: ordered blocks (a mosaic of boxes, a
file stack, a link preview card) whose cells are keyed by the item's
`MediaItemId` (`content_model`). The layout step is pure: the same input
gives an equal layout, so every value is a unit test.

Decisions: [ADR 047](../../docs/adr/047-message-media.md). Glossary:
[Chat Scroll](../../CONTEXT.md#message-media) (message media policy, media
layout) and [Content and Assets](../../docs/content/CONTEXT.md) (media item).

## Policy

`MessageMediaPolicy.android()`, `.ios()`, `.desktop()` hold each platform
family's defaults; `.platform()` picks the running app's. In a browser that
is `.web()`: the browser's operating system's family with the web's box
sizes by the window's width class (`MediaBoxSizing$Web`: 340 boxes on a
compact window, 420 on a wider one, a resize across 600 re-laying them out
at once), the card's media in the web's preview box, and the hover by the
pointer's input class. The host passes the window in the layout input
(`displaySize`, and `widthClass: ChromeWidthClass.of(context)`) and mounts
one `ChromeInputClassScope` near its root. A host replaces
the layout step whole (`copyWith(layoutStep:)`, any `MediaLayoutStep`), or
keeps the default `MediaLayoutPolicy` and replaces one part:

| Part | Role |
| --- | --- |
| `box` (`MediaBoxSizing`) | A single box's size and the width of a block spanning the media budget. `MediaBoxSizing$Android`, `$IOS`, `$Desktop` and `$Web` each list their values, each a field with `copyWith`. |
| `mosaicAlgorithm` (`MosaicAlgorithm`) | Two or more boxes into a mosaic. `GroupedMosaicAlgorithm` is the default, with rows bounded by half of `max(list width, screen height)`. The iOS policy uses `IosMosaicAlgorithm`: a fixed pattern by orientation for two to four boxes, else the best split into two to four rows, within the list class's max size (300 × 380 compact, 440 × 440 regular). The desktop policy uses `DesktopMosaicAlgorithm`, laid out at 430 and scaled to the block width. |
| `fit` (`MediaFitPolicy`) | Each box kind's fit mode alone: `crop`, `blurFit`, `cropIfVisible(fraction)`; and `album`, the fit of every box in a mosaic of two or more (`crop` on every platform). |
| `captionWidth` (`MediaCaptionWidthPolicy`) | The caption's width metrics. |

Beside the layout step, the policy holds the parts every step lays out by
and the cells draw by: `fileStack` (`MediaFileStackPolicy`: file and custom
items as rows in a vertical stack, with the bubble width rule
(`MediaFileStackWidth`), row metrics with and without a thumbnail
(`MediaFileRowMetrics`, grouped variants on desktop), name lines, pull-ups
between rows, the time's growth, the desktop footer line, thumbnail corners
(`MediaFileThumbCorners`), mirroring in right-to-left lists and the type
(`MediaFileText`)) and `linkPreview` (`LinkPreviewCardPolicy`, below). A
host's own step is handed both, so replacing the step keeps them. Then the
paint step's parts, each replaceable with `copyWith`: `corners`
(`MediaCornerPolicy`), `autoplay` (`MediaAutoplayPolicy`, a host flag),
`cells` (`MediaCellBuilders`), `chrome` (`MediaChromeSlots`) and
`transition` (`MediaTransitionPolicy`).

## Text and strings

The input's `text` (`MediaLayoutText`) is what the layout measures text with
and the cells paint it with: the chrome typography as the one base style,
the platform's text scaler, the host's media strings and the measure
(`MediaTextMeasure`, the framework painter by default). A host builds it
with `MediaLayoutText.of(context)` where the view is built, so a themed font
family or a larger text size lays out exactly the lines it draws. The words
(file sizes, the info and link lines, what a screen reader hears) are the
`media` group of the chrome strings (`ChromeStringsScope.mediaOf`); the
package ships none. English and Russian presets are in
`package:chrome_foundation/testing.dart`.

## Layout

`MessageMediaPolicy.layout(MediaLayoutInput)` returns a `MediaLayout`. The
input carries the items, the list width and screen, where the text sits
(`MediaCaptionPosition`), the bubble's surroundings (avatar, side button,
joined bubbles, outgoing), measured chrome widths (`MediaLayoutChrome`) and
an optional link preview. Never a message: the items may come from several.

Consecutive boxes (photo, video, animation) make a mosaic block; file and
custom kinds make a file stack; a mixed list gives consecutive blocks, and
the link preview's card comes last. Each `MediaCell` has a rect in layout
coordinates, a fit (none for a file row) and a `MediaNeighbour` per side
(bubble edge, text, item, adjacent bubble), which the paint step reads for
corner radii.

A layout with a caption carries `MediaWidthMetrics` from the step's
`MediaCaptionWidthPolicy`: `widenMedia` on Android (the caption wraps at
the bubble's max content width) and desktop (up to 430), `wrapAtMedia` on
iOS (at the media's max width). A host that passes the caption's measured
width (`captionWidth`) gets media widened to it, up to the policy's limit.

## File stack

Files never join a mosaic. Each file is a row; a file has a thumbnail when
its mime type is `image/*` or `video/mp4` or its descriptor carries one.
The stack block (`MediaBlock$FileStack`) reports each row's inner geometry
as a `MediaFileRow`: the control or thumbnail, the name's box and line
count, the info line, the desktop link line, whether the time sits on the
row (the last file), and the slot for the file's own caption
(`MediaLayoutInput.fileCaptionHeights`, measured by the host, whose text
body draws it). The layout measures names and info lines in the input's
`MediaLayoutText`.

## Paint

`MessageMediaPolicy.layout` resolves each cell's corner radii
(`MediaCell.radii`, a numeric `MediaCornerRadii` per corner, so two layouts
interpolate). A corner takes the bubble-edge radius only when both its
sides touch the bubble's edge; a side touching text or another item gives
the inner radius. A side joined to another bubble rounds only its corner
on the sender's side, and the bubble's tail may change the corner under
it. `MediaCornerPolicy.android()`, `.ios()` and `.desktop()` list the
values.

`MessageMediaView` paints a layout: each cell at its rect, keyed by its
`MediaItemId`, so a cell keeps its element and binding across any
re-layout. A cell is built by the policy's builder for its shape: `box`
(photo, video, animation; default `MediaBoxCell`) or `row` (file and
custom kinds; default `MediaRowCell`, which draws a `MediaFileRow`: the
control, or the thumbnail with the control centred on it, the name cut in
the middle (`MiddleElidedText`; a tooltip with the full name on desktop),
and the info line, which shows received / total while bytes arrive). Row
text is drawn in the layout's `MediaLayoutText` at the
`MediaFileStackPolicy`'s sizes; the tooltip is the chrome tooltip
(`ChromeTooltip`) with its own text root. Desktop rows mirror in a right-to-left list,
mobile rows do not. Replacing one builder leaves the other. The default cells draw through
`content_assets`' `ContentAssetView`, so the loading stages, status
control and badge are the media core's; a `ContentAssetProvider` sits
above the view. A box's fit is decided for the picture
(`MediaFit.drawIn`): cropped, or whole over bars filled with a blur of the
same cache entry (its preview or thumbnail until the content arrives).
Videos and animations play inline, muted, as `MediaAutoplayPolicy` says.

## Chrome slots

`MediaChromeSlots.android()`, `.ios()` and `.desktop()` lay chrome over
the cells; each slot is replaced on its own with `copyWith`:

| Slot | Default |
| --- | --- |
| `timePill` (`MediaTimePillPlacement`) | The pill is the host's chrome. When the time sits on the media (no caption below, no card, boxes last), `MessageMediaPolicy.layout` reports its rect as `MediaLayout.timePill`, at the bottom-right per platform. |
| `infoBadge`, `statusControl` | The loading stages' badge and the media core's status control, given to the slot as the stock part. |
| `spoiler`, `reveal` | `MediaSpoilerCover`: a blurred copy of the picture (the same cache entry) under drifting particles, clipped to the cell. `MediaSpoilerReveal` uncovers it: a circle from the touch point (`circle`), a spot after a short delay (`spot`), or a fade (`crossFade`). |
| `options`, `optionsAffordance` | `MediaOptionsDots` where `MediaOptionsPlacement` puts them: Android videos, animations and a file stack's first row; none on iOS and desktop. Hidden in compact mode (`MediaChromeContext`), on a preview, under a hidden spoiler and on a small image; fading out as the view's `selectionProgress` rises. |

The revealed fact is the chat's `MessageMediaState`
(`revealSpoiler(id, at:)`), so a re-layout or a new view keeps it; the
reveal's motion is the cell's, and reduce motion jumps to revealed. The
status control fades in with the reveal; it never takes a pointer of its
own (its taps are body part hits, below).
`MediaChromeSlots.spoilerRectOf` and `MediaOptionsPlacement.affordanceOf`
give the `spoiler` and `options` hit parts' rects.

## Gestures and semantics

Given the chat list's `ChatSelectionController` and the `messageId`,
`MessageMediaView` registers as the message's non-text body and answers
`inlineHitAt` with `ChatInlineHit.bodyPart` carrying a `MediaHitPart`:
the options affordance's hit area, a hidden spoiler, the status control
while it offers a download or a cancel, else the content. The viewport
arbitrates every tap: in message selection each part toggles the message,
a long press is the message's, a secondary click or the options open the
message menu with the part (`ChatMessageMenuRequest.partId`). No detector
of the media's own takes a tap.

In normal mode the view performs the part's action
(`MediaGesturePolicy.actionOf`, `MessageMediaPolicy.gestures`):

| Part | Android | iOS | Desktop | Web |
| --- | --- | --- | --- | --- |
| content | opens the viewer (`onOpenViewer`) | the same; a loading item cancels | the same; a loading item cancels | the same; a loading item cancels |
| status | downloads, cancels, retries | the same | the same | the same |
| hidden spoiler | reveals only | the same | the same | the same |
| cursor, hover | none | none | click cursor over a part, a 200 ms highlight on the item; plain in selection | as on desktop for a mouse; none for a touch screen or a stylus, read from each event's pointer kind |

An activation within 400 ms of the last accepted one is dropped
(`activationGuard`). A `MediaViewerRequest` carries the items to page
(a message's pictures together, a file alone), the index, the item's
rectangle at the tap, and `rectOf` by id (`MessageMediaState.rectOf`,
answered by every mounted view of the chat) for the frame the viewer
closes on.

Each item is one semantics node: its kind, then duration or size, then
progress while it loads (the host's media strings). The
node's tap opens the item; the status control and the options affordance
(`onItemMenu`) are separate actions; in message selection the tap toggles.

The package builds no menu. `MediaItemAction.allowedItemActions(item,
protection:, messageProtected:)` says which per-item actions (save, copy,
share, cancel download) the item's kind supports and the chat's
`ChatProtection.forMessage` allows; the host's menu and viewer build from
it.

## Outgoing messages

A host shows a message being sent by passing its `sendState`
(`MediaSendState.sending`, `failed`, or `none`) to `MessageMediaView`,
`MessageMediaTransition` or `MessageMediaBubbleLayout`. The uploads come
from the media scope: given the host's `TrackedTransfers`
(`ContentAssetScope.withMedia(tracked:)`, or an `AssetCacheScope(tracked:)`
of its own), each item's status control reads the upload by the item's
media key (its `ContentKey` mapped by `content_assets`):

| Upload | Cell |
| --- | --- |
| `AssetTransfer.sending(sent, total)` | the ring with the bytes sent and an upload's cancel |
| `AssetTransfer.sent` | the sent check (`MediaChromeSlots.sentCheck`, default `MediaSentCheck`) |
| `AssetTransfer.none` (published) | nothing; the local picture stays |

The cancel on an item of a message being sent is its cross: it goes to the
upload's owner through `TrackedTransfers.cancel`, which drops the item from
its job, and `onItemCancelled` hands the host the item's `MediaItemId`, so
the item leaves the message's list and exits under the layout transition.
A failed send shows no status control: the error badge and Retry / Delete
are the host's.

On iOS (`MessageMediaPolicy.sendFlight`, `MediaSendFlightPolicy.ios()`) a
cell built for the first time asks the chat's
`MessageMediaState.takeSendOrigin` once and flies from that rect to its own
over 300 ms, in the overlay, re-reading its rect every frame; reduce
motion shows it in place. The row's own appearance is the host's.

## Transitions

`MediaLayout.lerp(a, b, t)` interpolates two layouts cell by cell, matched
by `MediaItemId`: rect and each corner's radius (or the corners snap), the
fit and kind snap, block rects, the size, the time pill and the caption's
wrap width follow. A cell only in `b` enters at its rect; a cell only in
`a` is in the result's `exiting`, painted at its last rect until its exit
ends.

`MessageMediaTransition` is one message's clock: each new layout animates
from the frame on screen (so a change mid-flight continues from where it
is), and its `builder` gets every `MediaTransitionFrame` to drive the
bubble and the caption from the same clock. The widget is the frame's
size, so the row reports an interpolated height and the viewport's anchor
and follow-tail rules move the rows around it. `MediaLayoutTransition` is
the pure leg underneath.

| `MediaTransitionPolicy` | Android | iOS | Desktop |
| --- | --- | --- | --- |
| move | 250 ms, the list-item change curve | 400 ms, the system list curve; corners snap | none |
| exit | 120 ms fade; the move waits 120 ms | 250 ms fade | none |
| enter | 250 ms fade, scale 0.9 → 1 | 250 ms fade | none |

With `MediaQuery.disableAnimations` every change jumps to its end.

## Bubble layout

`MessageMediaBubbleLayout` is the optional bubble content: the media, the
caption (the host's text body), a header (name, forward, reply) and the
time pill, placed by the message's `invertMedia`. `MediaBubbleComposition`
says what the bubble holds; its `inputFor` tells the layout which media
sides touch text (caption above or below, header above, reactions below),
and `MediaBubbleShape.of` and `MediaBubbleTime.of` give the bubble's shape
(a media bubble has no tail; a caption below makes a tailed text bubble)
and where the time goes (over the media, on the last file row, under a
last card, or in the host's text).

The caption wraps at the metrics' width; the header is laid out to the
media's width and truncates there. An album has one caption, above or
below; each file of a stack keeps its own in its row's caption slot. The
widget runs `MessageMediaTransition` itself: an `invertMedia` flip slides
the caption to its other side and a caption edit (`captionRevision`)
cross-fades the old caption into the new, both on the media's clock, with
the `invertMedia` and `caption` triggers. The host keeps the bubble's fill
and tail around it.

## Link preview card

The `linkPreview` block is laid out by `LinkPreviewCardPolicy`
(`MessageMediaPolicy.linkPreview`; `android()`,
`ios()`, `desktop()`, every value a field). The host passes the page as
`MediaLinkPreviewInput` (the message id the media ids derive from, the
options, the action button's label, compact mode, the chat's direction);
nothing is passed while the page is pending, and a removed or empty page
makes no block.

| Part | Role |
| --- | --- |
| `LinkPreviewBlockStyle` | The quote block's bar (3), fill (0.10, 0.12 outgoing dark / 0.1 / 0.12) and radius (5 / 4 / 5) |
| `LinkPreviewCardMetrics` | Offsets in the bubble, insets, gaps, the thumbnail (48 / 54 / from the text), large media's caps, media corners (4 / 4 / 3), the button (42 / 36 / 36) |
| `LinkPreviewCardText` | Sizes, weights and line limits (the desktop's 5-line budget) |
| `LinkPreviewCardWidth` | `fillBudget` / `fitMedia` / `fitContent` |
| `LinkPreviewMediaSizeRule` | `small` or `large` from the options and each platform's `auto` default, over the host's `smallMediaTypes` |
| `LinkPreviewAppearForm` | `jump` / `fade` (250 ms) / `relayout` when the page arrives |
| `LinkPreviewCardPress` | The press over `ChromeInk`: ripple and bounce, the inset scale, or the ripple |
| `photoTapOpensPage`, `LinkPreviewEnlargeButton` | What a tap on the photo of a card with text does |
| `LinkPreviewTimePlacement` | The time under a last card: its own line, or inside the card |

The card's text is measured and drawn in the input's `MediaLayoutText`.

The block carries the page, the media as an ordinary `MediaItem`
(`MediaItemId.linkPreviewOf`) and its cell, and the `LinkPreviewCard`
geometry (text pieces, button, enlarge button, time slot). The media
loads, draws, hits and moves as any other item; small ↔ large, height and
above ↔ below go through `MediaLayout.lerp`, a new page cross-fades, and
the card fades in or shows at once per the appear form.

The card's area is a body part hit with a `LinkPreviewHitPart`: `body`
(the site name included) or `button`, both `activate`; the view calls the
host's `onLinkPreview` with the part and the page, behind the input guard.
A description link is an ordinary text link. The photo of a card with text
opens the page where `photoTapOpensPage` says, the desktop's enlarge
button the viewer. In message selection any tap toggles; a menu request
on the card carries the part. The press feedback yields its tap to the
viewport and never runs under a link, the button or the media. A view with
no message id has no card part: nothing hits the card and its nodes take
no tap. Colours are the host's (`LinkPreviewCardColors`), or the chrome
palette's accent when it passes none; the fill's share in a dark theme
follows the palette's brightness. One node reads "Page preview, title,
text"; the button is a node of its own. In a right-to-left chat the bar is
on the right and, on desktop, the thumbnail on the left.

## Geometry

| Type | Role |
| --- | --- |
| `SingleMediaLayout.compute` | The Android box clamp: scaled into `maxWidth × (maxWidth + 100)`, at least 120 high. |
| `GroupedMessages`, `GroupedMediaMember` | The default mosaic algorithm in abstract span units (`positionOf(id)`, `captionItemId`). |
| `GroupedMessagePosition`, `GroupedPositionFlags` | One cell's grid bounds, abstract size and outer edges. |
| `MosaicLayout`, `MosaicCellLayout` | The positions projected into pixels (`cellOf(id)`), rows by the width or by a given row height unit. |
| `MediaLayoutMetrics` | The mosaic's constants. |
| `MessageMediaHitPart`: `MediaHitPart`, `LinkPreviewHitPart` | The part a body part hit (`ChatInlineHit.bodyPart`) is on: a media item's content, status control, spoiler or options affordance, or a link preview card's body or button. The host reads it back from the activation and from the message menu request's `partId`. |

## Diagnostics

`media` events through `ChatDiagnostics.current` (`MediaOp`):
`layoutComputed` (trace) for every layout, `layoutFallback` (debug) when a
box takes a fallback rule (`mosaicRows` when an iOS pattern would leave a
box no area and the album is laid in rows), `unknownKind` (warning) when a
custom kind is drawn as a file row (once per kind for each diagnostics
sink), `cellFailed` (error, the `MediaBuilder`) when a cell builder or a
chrome slot throws or a cell's item is missing,
`spoilerRevealed` (debug) when a reveal starts (form, reduce motion),
`transitionStarted` and `transitionInterrupted` (trace) for each layout
change and each change mid-flight, `hit` (debug) when an activation
revealed a spoiler or cancelled a download, `activationDropped` (debug)
for a tap the input guard dropped, `viewerOpened` (info) and
`originRectMissing` (warning, at open or close: `MediaViewerMoment`); `hit`
also reports a card's `open` and `action` (`MediaHitOutcome`). For an outgoing message, `uploadState`
(debug) names each change of an item's upload (`sending`, `sent`, `none`)
with its media key, `itemCancelled` (info) the album's size before and after
a cross, and `sendOriginFlight` (debug) whether a cell given an origin flew. `linkPreview` / `cardShown` (debug,
`LinkPreviewCardOp`) names a shown card's media size, width rule and appear
form. They carry the chat, message and item ids, never a caption, a file
name or a page.

Timeline sections (`--dart-define=chat_scroll_view.trace=phase`):
`chat_scroll_view.media.layout`, `chat_scroll_view.media.lerp`,
`chat_scroll_view.media.cardLayout`, and at
`fine` `chat_scroll_view.media.cellBuild` per cell.

## Goldens

`test/goldens/` holds the single box and mosaic scenes, laid out by the
Android policy, and the painted view per platform policy (single box,
albums of two and three, of four and ten on iOS, a captioned box, a whole fit over blurred bars). Baselines are the CI runner's; compare or regenerate them
with `scripts/goldens [--update]`.
