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
| `mosaicAlgorithm` (`MosaicAlgorithm`) | Two or more boxes into a mosaic. `GroupedMosaicAlgorithm` is the default on every platform, with rows bounded by half of `max(list width, screen height)`. |
| `fit` (`MediaFitPolicy`) | Each box kind's fit mode: `crop`, `blurFit`, `cropIfVisible(fraction)`. |
| `fileRowHeight` | A file row's height until the file stack lays rows out. |

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
box takes a fallback rule, `unknownKind` (warning) when a custom kind is
drawn as a file row. They carry the chat, message and item ids, never a
caption, a file name or a page.

## Goldens

`test/goldens/` holds the single box and mosaic scenes, laid out by the
Android policy. Baselines are the CI runner's; compare or regenerate them
with `scripts/goldens [--update]`.
