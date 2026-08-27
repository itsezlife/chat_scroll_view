# message_media

Telegram-faithful **single** and **grouped** photo/video layout geometry, a
**per-chat grouped messages map**, group caption placement (plain text), and
muted placeholder paint for judging mosaics.

## Owns

- `computeSingleMediaSize` — single photo/video box clamps
- `GroupedMessages.calculate` / `GroupedMessagePosition` — photo/video mosaic
  (not documents stack layout)
- `GroupedMessagesMap` — disposable per-chat `groupId` → members / positions
- `GroupRowLayout` / `GroupRowCaption` — caption height on the owning edge row
  only (`captionAbove` supported; no entities)
- `MosaicLayout.project` — abstract positions → pixel rects + radii
- `MessageMediaPlaceholder` — solid fills in those rects

## Does not own

- Chat list fan-out / neighbor policy
- Image decode / download pipelines
- Caption entities / spoilers / rich text blocks
- Documents grouped stack layout
- `ChatDataSource` (host feeds the map; media APIs stay out of the DS)

## TRACE metrics

Canonical table: `MediaLayoutMetrics` dartdoc (`maxSizeWidth` 800,
`maxSizeHeight` 814, outer radius `bubbleRadius − 2`, inner `4`, cell gap `1`).

## Goldens

Baselines under `test/goldens/` use Linux as the reference platform. Refresh:

`flutter test test/message_media_placeholder_golden_test.dart --update-goldens --run-skipped`
