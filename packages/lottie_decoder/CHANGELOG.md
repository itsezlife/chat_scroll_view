# Changelog

All notable changes to `lottie_decoder` are documented in this file. This
package is pre-1.0.

## [Unreleased]

### Added

- A playback benchmark over the real native library (1, 8 and 32 stickers: tick, render round trip, upload, bytes per tick, pages), gated by the `benchmark` tag and `LOTTIE_PLAYBACK_BENCH=1`, reported against a committed baseline as ratios.
- `FrameCache`, `FrameCacheKey` and `FrameCacheFiles`: a RAM and disk store of
  compressed animation frames keyed by content, display size and engine
  version.
- `LottieEngine` and `InProcessLottieEngine`, `NativeFramePageMemory` and
  `LottieFrameRenderer`, tested against `FrameRendererContract` over the fake
  and the native binding.
- `LottieFrameScheduler`: the owner of a host's `FrameAtlas`, one batch of
  the latest wanted frames per `PlaybackClock.follow` tick, an idle sweep that
  frees the slots of unpainted leases, and failed jobs that stop being asked.
- `LottieAnimationPaintable` (frame from the paints' accumulated playback
  time, one frame ahead, rest frame, restart, freeze-and-continue across a
  pause) and `LottieStillPaintable`.
- `IsolateLottieEngine`: one render isolate that owns the binding, with
  `spawn` refusing an unavailable binding by naming the reason, and
  `LottieEngineContract` in `testing.dart`, run over every engine.
- `LottieDecoder`, the `Decoder` of `MediaForm.vectorAnimation`: thumbnail,
  first-frame and animated stages, the still above the largest size class,
  permanent failures, cancel that frees the handle.
- `LottieAnimationPaintable.onDispose`, run once on dispose so the decoder can
  free the engine handle.

- `FrameCache.invalidate` and `FrameCache.isDisposed`.
- `LottieEngine.renderCapturing` (a render that also returns each slot
  compressed, as `LottieCapture`) and `LottieEngine.restore` (decompress
  `LottieRestoreJob`s into slots); `InProcessLottieEngine(codec:)` and
  `IsolateLottieEngine.spawn(codecFactory:)` give an engine its frame codec,
  and one without a codec renders and restores nothing. `CountingLottieEngine`
  in `testing.dart`; the engine contract covers capture and restore.
- `LottieSource`, `LottieAnimationPaintable(cacheKey:)` and
  `LottieDecoder(cache:)`: the decoder names an animation in the cache by the
  SHA-256 of the file, the render size and `LottieNativeVersion.engine`.
  Depends on `package:crypto`.

### Changed

- **Breaking:** `LottieFrameRenderer` takes `engine:`, `memory:` and an
  optional `cache:` by name, and a frame job's `source` is a `LottieSource`
  (it was the bare `LottieHandle`); a source of another type is an
  `ArgumentError`. With a cache the renderer restores cached frames, stores
  the rest, and re-renders a frame whose entry will not restore after dropping
  that animation. A custom `LottieEngine` must implement the two new methods.

- `IsolateLottieEngine.close` lets requests already sent run to completion
  (a render's future no longer fails while native code may still write to its
  buffer); a failed `spawn` surfaces its own error and closes its ports.
- `LottieEngineClosed` and `LottieUnavailable` (both `StateError`s) replace bare
  `StateError`s for a closed engine and an unavailable binding.
- `LottieFrameSize.fitting` is the one render size of the decoder and the
  paintable; `LottieEngineJob.toBindingJob` the one job projection.
