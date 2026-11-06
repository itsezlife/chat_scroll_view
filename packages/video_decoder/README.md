# video_decoder

The video decoder adapter: the `Decoder` of `MediaForm.video`, the scheduler
that plays clips against the shared clock, and the engine seam under them.

- `VideoEngine` (web-neutral): `open`, `nextFrame` into a `Uint8List`,
  `rewind`, `close`, `dispose`. Frames of a clip come in order; looping is
  `rewind`. Premultiplied BGRA, tightly packed.
- `InProcessVideoEngine`: runs the binding on the calling isolate.
- `IsolateVideoEngine.spawn(workers: 2)`: workers own their clips; a clip is
  pinned to one worker, requests for it run in the order made.
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
- `maxAdvancing` (6) clips advance at once, the most recently leased; the
  others keep their last frame and resume, from where they stopped, when a
  slot frees.
- It follows `PlaybackClock` only while a lease exists, so the pause layers
  apply and an idle clock sleeps. Paintables hold and restart as the Lottie
  one does, with the same 500 ms resume gap.

## The video pool

`VideoFrameAtlas.create()` builds a `FrameAtlas` separate from the Lottie one
(default 32 MiB): its budget is its own, its pages are BGRA (the engine's byte
order, uploaded as `bgra8888`, so no channel is swapped on the way), and its
renderer copies already-decoded frames. When the pool is full, `acquire`
answers null and the paintable keeps its still.

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
