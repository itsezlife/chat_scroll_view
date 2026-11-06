# Changelog

All notable changes to `video_decoder` are documented in this file. The
format is loosely based on [Keep a Changelog](https://keepachangelog.com/);
this package is pre-1.0.

## [Unreleased]

### Added

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
