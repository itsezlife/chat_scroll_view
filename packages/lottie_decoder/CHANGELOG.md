# Changelog

All notable changes to `lottie_decoder` are documented in this file. This
package is pre-1.0.

## [Unreleased]

### Added

- `FrameCache`, `FrameCacheKey` and `FrameCacheFiles`: a RAM and disk store of
  compressed animation frames keyed by content, display size and engine
  version. Not wired into the renderer yet: nothing changes for existing hosts.
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

### Changed

- `IsolateLottieEngine.close` lets requests already sent run to completion
  (a render's future no longer fails while native code may still write to its
  buffer); a failed `spawn` surfaces its own error and closes its ports.
- `LottieEngineClosed` and `LottieUnavailable` (both `StateError`s) replace bare
  `StateError`s for a closed engine and an unavailable binding.
- `LottieFrameSize.fitting` is the one render size of the decoder and the
  paintable; `LottieEngineJob.toBindingJob` the one job projection.
