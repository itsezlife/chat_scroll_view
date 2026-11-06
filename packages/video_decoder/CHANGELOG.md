# Changelog

All notable changes to `video_decoder` are documented in this file. The
format is loosely based on [Keep a Changelog](https://keepachangelog.com/);
this package is pre-1.0.

## [Unreleased]

### Added

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
