# message_media

Telegram-faithful **single** and **grouped** photo/video layout geometry, plus
muted placeholder paint for judging mosaics.

## Owns

- `computeSingleMediaSize` — single photo/video box clamps
- `GroupedMessages.calculate` / `GroupedMessagePosition` — photo/video mosaic
  (not documents stack layout)
- `MosaicLayout.project` — abstract positions → pixel rects + radii
- `MessageMediaPlaceholder` — solid fills in those rects

## Does not own

- Per-chat grouped messages map
- Chat list fan-out / neighbor policy
- Image decode / download pipelines
- Documents grouped stack layout

## TRACE metrics

Canonical table: `MediaLayoutMetrics` dartdoc (`maxSizeWidth` 800,
`maxSizeHeight` 814, outer radius `bubbleRadius − 2`, inner `4`, cell gap `1`).

## Goldens

Baselines under `test/goldens/` use Linux as the reference platform. Refresh:

`flutter test test/message_media_placeholder_golden_test.dart --update-goldens --run-skipped`
