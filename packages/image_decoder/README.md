# image_decoder

A `Decoder` adapter for `catalog_assets` over the engine's image codecs: PNG,
JPEG, WebP, GIF and BMP stills, and animated WebP and GIF frame sequences.
Content is decoded to fit inside the entry's `AssetSpec`, keeping its aspect
ratio and never scaled up, and painted centred in the surface's rectangle.

## Types

| Type | Role |
| --- | --- |
| `ImageCodecDecoder` | The decoder. Stateless and `const`; the host registers it under each `MediaForm` whose content arrives in these formats. |

```dart
final decoders = DecoderRegistry()
  ..register(MediaForm.still, const ImageCodecDecoder())
  ..register(MediaForm.video, const ImageCodecDecoder()); // animated images
final pipeline = AssetPipeline(fetcher: myFetcher, decoders: decoders);
```

## What it reports

| Request | Stage | Tier |
| --- | --- | --- |
| thumbnail | `placeholder`: the first frame | still |
| content, `AssetVariant.firstFrame` | `firstFrame`: the first frame | still |
| content, one frame | `full`: the frame | still |
| content, several frames | `full`: the playing image | animated |

Undecodable data fails the attempt as permanent; nothing is painted for it.

## Playback

A playing image decodes one frame ahead of the one it shows instead of every
frame up front, so it costs two frames of pixels however long it is. Its frame
follows the playback time of the shared clock: frames keep their own
durations, a jump in time (playback resumed) shows the next frame at once
rather than racing through the ones missed, and a frame of 10 ms or less is
shown for 100 ms, as browsers do. It loops for good.

## Not covered

Vector animations (Lottie) and video codecs (WebM) are other adapters. A
`FetchedFile` is read with `ImmutableBuffer.fromFilePath`, which the web does
not support; a fetcher for the web hands bytes.
