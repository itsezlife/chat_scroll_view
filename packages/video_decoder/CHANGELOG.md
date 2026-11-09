# Changelog

All notable changes to `video_decoder` are documented in this file. The
format is loosely based on [Keep a Changelog](https://keepachangelog.com/);
this package is pre-1.0.

## [Unreleased]

### Changed (a clip that comes back goes on at once)

- A clip that left the screen keeps the frames it had decoded ahead, not only
  its time and its decoder's position: back on screen it shows the next frame
  at its time. Before, it held the frame it came back on for three or four
  frames' time and then skipped those frames, which read as a jump. The kept
  frames cost at most `VideoFrameScheduler.keptAheadBytes` together (12 MiB
  by default; the clip away longest gives its frames up first, and then
  comes back as before); `releaseIdle` and `forget` drop them, and
  `bufferedBytes` counts them until then.
- A clip that comes back starts its timing at its next want: the time it was
  away is never played, even when its paintable counted it.

### Changed (each clip waits only for its own frame)

- `VideoFrameScheduler` keeps a frame in flight per clip, not one batch for
  all: a clip whose frame is still being drawn or written is skipped on a
  tick and the others go on. Each clip on a texture is its own write, so a
  slow worker no longer holds the posts of clips on the other workers.

### Added (the panel keeps its animations)

- `VideoAnimationPaintable.firstFrame` is its first-frame still, which a
  sibling binding borrows instead of the frame the clip is at.

### Added (half frame rate)

- `VideoFrameScheduler.want` takes `frameStep`: with 2 the clip keeps only the
  first decoded frame of a pass and every second one after it, so it draws or
  posts half as many. `VideoAnimationPaintable` passes
  `AssetPaintContext.frameStepFor` of the clip's rate, so a surface at half
  rate (`AssetProfile.halfFrameRate`) shows a 60 fps clip at 30. The default
  step of 1 plays as before.

### Changed

- The still and the playing sprite are placed by `AssetPaintContext.fit`
  (contain by default, cover for a surface that asks).
- The cap on playing clips no longer freezes the oldest. `maxAdvancing` now
  defaults to 12 and counts the clips served per tick: past it the slots
  rotate (overdue clips first, then the most recently leased half, then
  round-robin), so every visible clip updates at least every `maxStaleness`
  (250 ms) as far as the cap allows. Clip time runs for every playing clip;
  `maxAdvancing` is settable; clips unpainted for `visibleWindow` take no
  slot. Fixes GIFs stopping in the panel and in the chat while it is open.
- The default thumbnail decode is `MiniThumbnail.decode`: at most 40 px on
  the longer side, blurred once, so painting a loading clip's thumbnail is one
  small image draw. Pass `decodeImage` for the previous full-size decode.


### Added

- `WebVideoEngine` (`package:video_decoder/web.dart` for the browser end): a
  `VideoEngine` that plays each clip in a hidden, muted `<video>` element and
  reads presented frames back through a canvas as premultiplied BGRA. Browsers
  decode in real time, so `nextFrame` waits for the next presented frame and
  `VideoInfo.frameRate` is 0; `hasAlpha` is read from the first frame; more
  than `maxElements` (16) open clips are refused with `limitExceeded`; GIF is
  refused as `unsupported`. Existing hosts are not affected: the engine and its
  `VideoElementPort` seam are neutral Dart and tested on the VM with
  `FakeVideoElements` (in `testing.dart`) and the engine contract.
- `VideoDecoder`, the `Decoder` of `MediaForm.video`: a still at the display
  size (snapped to the video pool's size classes, aspect kept), then an animated
  `VideoAnimationPaintable`. A refused file fails the decode with
  `VideoDecodeRejected` carrying the binding's reason.
- `VideoFrameScheduler`: decodes each playing clip three frames ahead with one
  request in flight, shows the newest ready frame at or before the clock (a
  slow engine skips frames, it never queues), loops by rewinding, and lets at
  most six clips advance at once. The ones held back resume where they stopped.
- `VideoFrameAtlas.create`: a frame pool of its own (32 MiB by default, BGRA
  pages) so video and Lottie budgets stay independent. Existing hosts are not
  affected; nothing registers a video decoder until a host does.
- `VideoAnimationPaintable` and `VideoStillPaintable`, with the sprite and
  `advancePlayback` hooks panel batching uses.

- `VideoEngine`, the web-neutral seam over a `video_native` binding: open a
  file as a `VideoClip`, pull its frames in order into a caller's buffer,
  rewind to loop, close. Decoding is sequential by contract; there is no seek.
- `InProcessVideoEngine` (synchronous core, for tests and hosts without an
  isolate) and `IsolateVideoEngine`, a pool of 1 to 4 long-lived worker
  isolates (default 2). A clip is pinned to the worker that opened it, so a
  clip's requests run in the order they were made while different clips decode
  concurrently. A worker that ends fails only its own clips with
  `VideoClipLost`; the others go on. Frames cross isolates as a transferable
  copy (see the class docs for why not zero-copy yet).
- `FakeVideoEngine` and `VideoEngineContract` in `testing.dart`, run against
  the fake, the in-process engine and the isolate engine, the last two over
  both the fake binding and the real library (skipped with a reason when the
  library is not bundled).
