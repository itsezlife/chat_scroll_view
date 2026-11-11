# Changelog

All notable changes to `lottie_decoder` are documented in this file. This
package is pre-1.0.

## [Unreleased]

### Changed (a hidden panel gives its textures back)

- A kept lease whose paintable leaves the screen (a held surface that shows
  nothing of it: a hidden panel) gives its texture back keeping its frame,
  and stays, kept. It used to keep the texture, so a hidden panel held a
  texture per cell, the pool's budget was spent on them, and a chat sticker
  that came back played from a page, uploading it on every frame. Its next
  want takes that texture back and shows it at once, rendering nothing; one
  whose frame the pool forgot (past `keptFrameBytes`, or taken for room)
  plays from a page slot until a texture is free. A kept lease on screen
  (not left) keeps its texture as before.

### Added (readings for a profiler)

- `LottieFrameScheduler.leasePlaces()`: how many leases play on textures,
  on page slots alone (naming them), on slots for a canvas, and kept.
- A playing animation's lease key reads as its content and size
  (`<content>@<w>x<h>`), so a page upload's keys say whose frames they are.

### Fixed (playback that resumes goes on at once)

- The idle sweep releases nothing while the playback clock is paused, and
  counts the pause as painted. A paused clock paints nothing, so after a
  second or two every lease on screen looked unwanted and went: on resume
  each cell took a new lease, and with more cells on screen than the texture
  pool keeps frames for, they took each other's kept textures, so every cell
  showed its still for three posts (about 100 ms) and then skipped ahead.

### Changed (a cell that comes back goes on at once)

- A lease that takes its kept texture back renders the frame after the one
  on it, not that frame again: one render less, and no doubled first frame.

### Changed (an animation above the cap plays)

- A `full` decode whose spec is above 512 px (`LottiePixelJob.maxEdge`) now
  renders at 512 and reports a `LottieAnimationPaintable`, which the surface
  draws scaled up; it used to report the first-frame still as `full`, so a
  content preview of about 600 px stood still (native-media ticket 128). Code
  that expected a still above the cap gets an animated paintable, and the
  frame cache gets a key at 512 for it.

### Added (a pool of render isolates)

- `IsolateLottieEngine.spawn(workers:)` starts one to `maxWorkers` (4) render
  isolates; `defaultWorkers` is the core count less one, at most four. A
  handle stays on the isolate that loaded it, and the handles the engine
  gives out encode it, so with more than one isolate they are not the
  binding's ids. A request over several isolates' handles is split and
  answered in job order; one isolate ending closes the engine. The default
  stays one isolate.
- `LottieFrameScheduler` sends the largest texture frames of a tick first.

### Changed (each lease waits only for its own frame)

- `LottieFrameScheduler` keeps a frame in flight per lease, not one batch
  for all: a lease whose frame is still out is skipped on a tick and every
  other lease goes on. Each lease on a texture is its own write, so its post
  lands when its own frame is done; the page slots of a tick still share one
  atlas batch. A writer now sees one job per `write` call from the scheduler.

### Changed (the panel keeps its animations)

- The `full` stage charges its first-frame still plus the encoded size once
  (was four times it): a 160 px cell of a 181 KB sticker counts about
  0.28 MiB instead of 0.8 MiB, so the cells a panel scrolled out stay cached.
- `LottieAnimationPaintable.firstFrame` is its first-frame still, which a
  sibling binding borrows instead of the frame the loop is at.

### Changed (a fill per parity, ticket 102)

- The frame cache keeps an animation as two fills, its even frames and its
  odd frames (`FrameParity`), each completed, written and evicted on its own.
  A playback at half rate asks only for the even frames, so before this its
  fill never completed, never reached the disk, and re-rendered once the RAM
  tier dropped it; now its even file is written after one pass and serves the
  next. A playback at full rate restores the even frames from that file and
  fills the odd ones. A full-rate animation is two files.
- `FrameCacheKey.toFileStem` takes the parity; `FrameCacheCodec.header`,
  `headerLength` and `table` take it too. `CachedFrameFile.index` stays the
  animation's frame; the reader finds it in the file of its parity.
  `FrameFileReader` keeps 64 files open by default (was 32).
- File format version 3 (a parity field after the hash length). Version 2
  files have no parity in their name, are never opened, and age out.

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

### Added (half frame rate)

- `LottieAnimationPaintable` honours `AssetPaintContext.halfFrameRate`: an
  animation above 30 fps asks only for the even frames of a pass, so a small
  sticker in a content grid renders and posts 30 frames a second instead of
  60, on a page slot and on a texture alike. Paints at full rate are
  unchanged.

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
