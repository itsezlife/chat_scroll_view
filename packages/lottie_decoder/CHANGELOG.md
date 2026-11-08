# Changelog

All notable changes to `lottie_decoder` are documented in this file. This
package is pre-1.0.

## [Unreleased]

### Changed (frames read from the file, ticket 98)

- A persisted animation's frames are read one at a time from its file by the
  engine that restores them (`FrameFileReader` on the render isolate);
  `FrameCache` keeps no bytes for it. `FrameCache.frame` returns a
  `CachedFrame` (`CachedFrameBytes` or `CachedFrameFile`) instead of bytes,
  `open` returns a `bool` and reads no frame, and `LottieRestoreJob.frame` /
  `LottieTextureRestore.frame` carry a `CachedFrame`.
- The RAM tier never evicts an animation used within `playingFor` while an
  idle one can go; when all play it drops the fill that started last. Complete
  animations leave RAM once written. `FrameCache.residentBytes` reports what
  it holds.
- `FrameCacheFiles.read` is gone; `pathOf` names an entry's file and `write`
  takes the entry as chunks. The file format is version 2 (no payload CRC);
  version 1 files serve nothing and are deleted on first use.

### Changed (disk budget optional)

- `FrameCache.diskBudgetBytes` may be null: the disk tier then evicts
  nothing, for a host that keeps the directory in a store of its own (one
  folder for all media, kept by last use). The default stays 128 MB, so a
  host that passes nothing sees no change; a file the host's store removed is
  a miss, rendered and written again.

### Changed (vm/js forks, no public top-level functions)

- The default content hasher is `LottieDecoder.sha256OffIsolate`, no longer
  the top-level `sha256OffIsolate`; code that passed it by name renames it.
- The platform forks live in `src/environment_specific/` as `_vm` / `_js`
  pairs whose hooks are `$`-named (`$openFrameCacheFiles`, `$readFileBytes`);
  `DirectoryFrameCacheFiles` keeps its name and its barrel export.

### Added (web engine)

- `WebWorkerLottieEngine`, the web's `LottieEngine` over a `LottieWorkerPort`
  (the Lottie worker protocol of `lottie_native/web`), `LottieWorkerError` and
  `LottieWorkerStatus` (the load statuses, held to `chat_lottie.h` by a test).
- `JsLottieWorkerPort` and `JsLottieWorker.spawnFromUrls`, the browser
  implementation over `package:web`, in `package:lottie_decoder/web.dart`
  (a web build imports it; the main library stays free of `dart:js_interop`).
  Compile-checked, not run in a browser.
- `FakeLottieWorker` (`testing.dart`) and `FakePixelLottieEngine.reject`.
- `LottieUnavailable.reason`, the worker's own words when it gave any.
- Depends on `web`; `fake_async` for tests.

### Changed (web-compilable core, breaking)

- `LottieEngine` is now the neutral interface: `load`, `renderPixels`,
  `dispose`, `close`. `renderBatch`, `renderCapturing` and `restore` moved to
  the native-only `LottieSlotEngine`, which `InProcessLottieEngine` and
  `IsolateLottieEngine` implement. Code that called those methods, or built
  `LottieFrameRenderer` or `LottieDecoder` from a variable typed
  `LottieEngine`, types it `LottieSlotEngine`; a custom `LottieEngine` now
  implements `renderPixels` and no longer the slot methods. `LottieDecoder`
  accepts any `LottieEngine`, and draws the first frame through
  `renderPixels`.
- `FrameCache(directory: Directory?)` is `FrameCache(directoryPath: String?)`.
  `FrameCacheFiles` is an interface; the directory implementation is
  `DirectoryFrameCacheFiles` (a test subclass of the old class extends that
  and passes a path). On the web a non-null path is an `ArgumentError`.
- The barrel exports the files that need `dart:ffi`, `dart:io` or
  `dart:isolate` only where they exist; every VM importer sees the same names
  as before, and the package compiles for the web (`web_compile_test`).
- `LottieDecoder` reads a `FetchedFile` through the `$readFileBytes` hook:
  `dart:io` on the VM, an `UnsupportedError` (a failed decode) on the web.

### Added (web-compilable core)

- `LottiePixelJob` and `LottiePixels`, the `renderPixels` job and result;
  `LottiePixelJob.maxEdge` is the size limit that `LottieRenderJob.maxEdge`
  has natively (a test holds them equal).
- `PixelCopyFrameRenderer`: a `FrameRenderer` over any `LottieEngine` that
  copies the pixels it returns into any `FramePageMemory`; no frame cache.
- `FakePixelLottieEngine`, `LottieSlotEngineContract` and `renderPixels`
  cases in `LottieEngineContract` (`testing.dart`).

### Changed (pages sized by class, breaking)

- `NativeFramePageMemory()` takes no page side: `page(i, side:)` and
  `addressOf(i, side:)` make the page at the side of its slot, `sideOf(i)`
  answers it, and a live page asked for at another side is a `StateError`.
  Code that built `NativeFramePageMemory(pageSide: ...)` drops the argument.
- `LottieFrameRenderer` writes at `(top * side + left) * 4` with a stride of
  `side * 4`, `side` being `FrameSlot.pageSide`.
- The playback benchmark's baseline moves: one 128 px sticker uploads 256 KiB a
  tick (was 4 MiB), eight 512 KiB, 32 stickers 2 MiB (were 4 MiB each); at 32
  the eight smaller uploads take longer in total than the one large one did.

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
