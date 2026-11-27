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
family's defaults; `.platform()` picks the running app's (on the web, its
operating system's family until the web's own sizes land). A host replaces
the layout step whole (`copyWith(layoutStep:)`, any `MediaLayoutStep`), or
keeps the default `MediaLayoutPolicy` and replaces one part:

| Part | Role |
| --- | --- |
| `box` (`MediaBoxSizing`) | A single box's size and the width of a block spanning the media budget. `MediaBoxSizing$Android`, `$IOS` and `$Desktop` each list their values, each a field with `copyWith`. |
| `mosaicAlgorithm` (`MosaicAlgorithm`) | Two or more boxes into a mosaic. `GroupedMosaicAlgorithm` is the default, with rows bounded by half of `max(list width, screen height)`. The iOS policy uses `IosMosaicAlgorithm`: a fixed pattern by orientation for two to four boxes, else the best split into two to four rows, within the list class's max size (300 × 380 compact, 440 × 440 regular). The desktop policy uses `DesktopMosaicAlgorithm`, laid out at 430 and scaled to the block width. |
| `fit` (`MediaFitPolicy`) | Each box kind's fit mode alone: `crop`, `blurFit`, `cropIfVisible(fraction)`; and `album`, the fit of every box in a mosaic of two or more (`crop` on every platform). |
| `fileRowHeight` | A file row's height until the file stack lays rows out. |

Beside the layout step, the policy holds the paint step's parts, each
replaceable with `copyWith`: `corners` (`MediaCornerPolicy`), `autoplay`
(`MediaAutoplayPolicy`, a host flag), `cells` (`MediaCellBuilders`) and
`transition` (`MediaTransitionPolicy`).

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
custom kinds; default `MediaRowCell`, interim until the file stack lays
rows out). Replacing one leaves the other. The default cells draw through
`content_assets`' `ContentAssetView`, so the loading stages, status
control and badge are the media core's; a `ContentAssetProvider` sits
above the view. A box's fit is decided for the picture
(`MediaFit.drawIn`): cropped, or whole over bars filled with a blur of the
same cache entry (its preview or thumbnail until the content arrives).
Videos and animations play inline, muted, as `MediaAutoplayPolicy` says.

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

## Geometry

| Type | Role |
| --- | --- |
| `computeSingleMediaSize` | The Android box clamp: scaled into `maxWidth × (maxWidth + 100)`, at least 120 high. |
| `GroupedMessages`, `GroupedMediaMember` | The default mosaic algorithm in abstract span units (`positionOf(id)`, `captionItemId`). |
| `GroupedMessagePosition`, `GroupedPositionFlags` | One cell's grid bounds, abstract size and outer edges. |
| `MosaicLayout`, `MosaicCellLayout` | The positions projected into pixels (`cellOf(id)`), rows by the width or by a given row height unit. |
| `MediaLayoutMetrics` | The mosaic's constants. |
| `MessageMediaHitPart`: `MediaHitPart`, `LinkPreviewHitPart` | The part a body part hit (`ChatInlineHit.bodyPart`) is on: a media item's content, status control, spoiler or options affordance, or a link preview card's body or button. The host reads it back from the activation and from the message menu request's `partId`. |

## Diagnostics

`media` events through `ChatDiagnostics.current` (`MediaOp`):
`layoutComputed` (trace) for every layout, `layoutFallback` (debug) when a
box takes a fallback rule (`mosaicRows` when an iOS pattern would leave a
box no area and the album is laid in rows), `unknownKind` (warning) when a custom kind is
drawn as a file row, `cellFailed` (error) when a cell builder throws or a
cell's item is missing, `transitionStarted` and `transitionInterrupted`
(trace) for each layout change and each change mid-flight. They carry the
chat, message and item ids, never a caption, a file name or a page.

Timeline sections (`--dart-define=chat_scroll_view.trace=phase`):
`chat_scroll_view.media.layout`, `chat_scroll_view.media.lerp`, and at
`fine` `chat_scroll_view.media.cellBuild` per cell.

## Goldens

`test/goldens/` holds the single box and mosaic scenes, laid out by the
Android policy, and the painted view per platform policy (single box,
albums of two and three, of four and ten on iOS, a captioned box, a whole fit over blurred bars). Baselines are the CI runner's; compare or regenerate them
with `scripts/goldens [--update]`.
