# message_media

Message media display. This first part holds the geometry a **message media
policy** lays **media items** out with: the single box size and the mosaic,
every cell addressed by its item's `MediaItemId` (`content_model`).

Decisions: [ADR 047](../../docs/adr/047-message-media.md). Glossary:
[Chat Scroll](../../CONTEXT.md#message-media) (message media policy, media
layout) and [Content and Assets](../../docs/content/CONTEXT.md) (media item).

## Types

| Type | Role |
| --- | --- |
| `computeSingleMediaSize` | The box of one photo, video or animation at a max width: scaled into `maxWidth × (maxWidth + 100)`, at least 120 high. |
| `GroupedMediaMember` | One item's input to the mosaic: its id, aspect, kind and caption flags. |
| `GroupedMessages` | The default mosaic algorithm for two or more boxes, in abstract span units: one `GroupedMessagePosition` per member (`positionOf(id)`), the caption owner (`captionItemId`) and placement (`captionAbove`). |
| `GroupedMessagePosition`, `GroupedPositionFlags` | One cell's grid bounds, abstract size and outer edges. |
| `MosaicLayout`, `MosaicCellLayout` | The positions projected into a pixel width: each cell's rect and corner radii, with a 1 px seam (`cellOf(id)`). |
| `MediaLayoutMetrics` | The layout's constants, which become the policy's values. |
| `MessageMediaHitPart`: `MediaHitPart`, `LinkPreviewHitPart` | The part a body part hit (`ChatInlineHit.bodyPart`) is on: a media item's content, status control, spoiler or options affordance, or a link preview card's body or button. The host reads it back from the activation and from the message menu request's `partId`. |

Photo, video and animation share one geometry; a file or custom kind is a
file row, not a box.

## Goldens

`test/goldens/` holds the single box and mosaic scenes. Baselines are the CI
runner's; compare or regenerate them with `scripts/goldens [--update]`.
