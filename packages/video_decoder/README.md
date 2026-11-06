# video_decoder

The video decoder adapter: the `Decoder` of `MediaForm.video`, the scheduler
that plays clips against the shared clock, and the engine seam under them.

- `VideoEngine` (web-neutral): `open`, `nextFrame` into a `Uint8List`,
  `rewind`, `close`, `dispose`. Frames of a clip come in order; looping is
  `rewind`. Premultiplied BGRA, tightly packed.
- `InProcessVideoEngine`: runs the binding on the calling isolate.
- `IsolateVideoEngine.spawn(workers: 2)`: workers own their clips; a clip is
  pinned to one worker, requests for it run in the order made.
- `WebVideoEngine`: the browser's decoder, a hidden `<video>` per clip behind
  `VideoElementPort`; `package:video_decoder/web.dart` adds `JsVideoElementPort`.
- `VideoDecoder`: decodes at the display size and reports the stages below.
- `VideoFrameScheduler`: decodes each playing clip a few frames ahead and
  draws the frame the clock names.
- `VideoAnimationPaintable` / `VideoStillPaintable`: what the cache paints.
- `VideoFrameAtlas.create`: the video pool, a `FrameAtlas` of its own.
- `testing.dart`: `FakeVideoEngine` and `VideoEngineContract`.

## The decoder

| Request | Reports |
| --- | --- |
| thumbnail (an ordinary image) | `placeholder`, a still |
| content, first frame only | `firstFrame`, a still |
| content, full | `firstFrame` (a still), then `full` (animated tier) |

The size is the spec's longer side snapped up to a pool class (64, 128, 256,
512; never above), the clip's aspect kept. A clip is opened once at a square of
that edge to learn its aspect and again at the fitted size when it is not
square. A refused file ends in `fail(VideoDecodeRejected(reason), permanent)`;
the leaf keeps its placeholder.

## Playing: ring, cap, loop

A video decodes in order and cannot seek, so the scheduler keeps a ring per
advancing clip:

- `prefetch` (3) frames ahead of the clip time, one `nextFrame` in flight per
  clip, never queued.
- The frame on show is the latest with a presentation time at or before the
  clip time; when decoding is behind, the newest ready frame wins and older
  ones are dropped unshown.
- Clips loop forever: at the end of the stream the scheduler rewinds and the
  timeline continues. With no declared duration the pass ends where the stream
  does.
- A visible clip keeps playing. `maxAdvancing` (12) clips get a slot per
  tick (a slot starts a decode or draws a frame); every clip keeps its own
  clock, so past the cap the slots rotate and a clip only updates less often,
  never freezes. Order: a clip that wants service and waited `maxStaleness`
  (250 ms) first; then the foreground (the `maxAdvancing ~/ 2` most recently
  leased); then the others round-robin. A clip not painted for
  `visibleWindow` (150 ms) takes no slot, and the sweep frees its lease.
  `maxAdvancing` can be changed at run time.
- It follows `PlaybackClock` only while a lease exists, so the pause layers
  apply and an idle clock sleeps. Paintables hold and restart as the Lottie
  one does, with the same 500 ms resume gap.

## The video pool

`VideoFrameAtlas.create()` builds a `FrameAtlas` separate from the Lottie one
(default 32 MiB): its budget is its own, its pages are BGRA (the engine's byte
order, uploaded as `bgra8888`, so no channel is swapped on the way), and its
renderer copies already-decoded frames. When the pool is full, `acquire`
answers null and the paintable keeps its still.

## On the web

```dart
import 'package:video_decoder/web.dart';

final engine = WebVideoEngine(createPort: JsVideoElementPort.create);
```

Compose it with the scheduler and atlas as below. Differences from the native
engines:

- **Real time.** The browser presents frames when it decides; `nextFrame` waits
  for the next one (`requestVideoFrameCallback`, or an animation frame in which
  `currentTime` moved), and the scheduler already skips what it is late for.
  `frameRate` is 0.
- **Alpha** is what the browser decodes; `hasAlpha` is true only if the first
  frame, drawn to a canvas, has a transparent pixel. Canvas pixels come back
  straight, so the engine premultiplies them and swaps to BGRA.
- **Cap.** `maxElements` (16) open clips; past it `open` is rejected with
  `VideoRejection.limitExceeded`. Closing a clip removes its element.
- **Timeouts.** A video not ready within `metadataTimeout` (10 s) is rejected
  as `unsupported`; `dispose` waits `disposeTimeout` (2 s) for frames under way,
  then fails them. A hidden tab presents no frames.
- GIF is not playable in a `<video>` and is refused.

`JsVideoElementPort` is compile-checked on the VM side (`web_compile_test`) and
has run only in a headless Chrome; the engine's rules are tested over
`FakeVideoElements`.

## Host recipe

```dart
try {
  final engine = await IsolateVideoEngine.spawn(); // throws when unavailable
  final scheduler = VideoFrameScheduler(
    engine: engine,
    atlas: VideoFrameAtlas.create(),
    clock: clock,
  );
  decoders.register(
    MediaForm.video,
    VideoDecoder(engine: engine, scheduler: scheduler),
  );
} on Object catch (reason) {
  // No decoder: video keeps its placeholder. Log it once.
}
```

At shutdown dispose the scheduler, then the engine.

The native tests need the `video_native` library (see its README); without it
they are skipped with a reason.
