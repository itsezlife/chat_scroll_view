# lottie_decoder

The Lottie adapter for the frame pool
([ADR 042](../../docs/adr/042-native-media-decoding.md), ADR 022 "dynamic frame
pages"): an async engine seam over a `lottie_native` binding, native page
memory a render isolate can write, and a `FrameRenderer` that draws into it.

## Types

| Type | Role |
| --- | --- |
| `LottieEngine` | The async face of a `LottieBinding`: `load`, `renderBatch` (of `LottieEngineJob`), `renderCapturing` (the same, and each rendered slot comes back compressed as a `LottieCapture`), `restore` (decompress `LottieRestoreJob`s into slots: `ok`, or `failed` with the slot untouched), `dispose`, `close` (idempotent; requests already made run to completion first; later calls throw `LottieEngineClosed`, a `StateError`). |
| `LottieEngineJob` | A render job whose target is an `int` address, so it crosses isolates. |
| `InProcessLottieEngine` | Runs a binding on the calling isolate, and a `LottieFrameCodec` if given one. With `FakeLottieBinding` it is the engine fake. |
| `IsolateLottieEngine` | One long-lived render isolate that owns the binding and every handle. `spawn({bindingFactory, codecFactory})` builds the binding and the frame codec inside the isolate (the codec only if the binding is available, and dropped if it is not; compressed bytes cross as `TransferableTypedData`) and throws a `LottieUnavailable` (a `StateError`) carrying the `LottieAvailability` when the binding is unavailable; any other start-up failure surfaces as it happened, and the isolate and ports are released. One request failing throws a `RemoteError` and spares the engine; the isolate ending fails every pending request with `LottieEngineClosed` and closes the engine. Requests run in arrival order. A native fault ends the process and cannot be caught. |
| `LottieEngineContract` (`testing.dart`) | The behaviour every engine shares, run over the in-process engine and over the isolate engine on the fake and on the real binding. |
| `NativeFramePageMemory` | `FramePageMemory` in `calloc`ed memory (a Dart-heap list cannot be written from another isolate). `addressOf(page)`, `drop`, `dispose`. |
| `LottieFrameScheduler` | The one owner of the host's `FrameAtlas`: follows `PlaybackClock` while a lease exists, renders the wanted frames as one batch per tick, and frees a slot after one to two idle periods (default 1 s) by a single sweep timer. The sweep uses a real `Timer` by design: it keeps counting while the clock is paused, and a repaint after a long pause reacquires the entry and draws the last rendered frame, not the still. |
| `LottieFrameSize` | The one render size (`fitting(info, edge)`) the decoder and the paintable share. |
| `LottieAnimationPaintable` / `LottieStillPaintable` | The animation (pull-driven, one scheduler key per animation, `onDispose` frees its handle) and a decoded still. |
| `LottieDecoder` | The `Decoder` for `MediaForm.vectorAnimation`, built from an engine, the scheduler and two injectable image steps (`decodeImage`, `uploadPixels`). |
| `LottieSource` | A frame job's `source`: the `LottieHandle`, the animation's frame count and its `FrameCacheKey?`. |
| `LottieFrameRenderer` | `FrameRenderer` over an engine, one memory and an optional `FrameCache`; a job's `source` is a `LottieSource`. |
| `CountingLottieEngine` (`testing.dart`) | Forwards to an engine and counts the jobs rendered and restored, for "this pass rendered nothing". |

## Host contract

| The host provides | The host must not |
| --- | --- |
| An engine over an available binding, and the one `NativeFramePageMemory` the renderer and the pool share | Pass the renderer another memory (`StateError`) or a job whose `source` is not a `LottieSource` (`ArgumentError`) |
| `dispose` for each loaded handle and `close` for the engine | Use a view from `page` after `drop` or `dispose` |
| `dispose` for the `FrameCache`, before `close` for the engine | Give one cache directory to two caches |

## The decoder

| Request | Reports |
| --- | --- |
| thumbnail (an ordinary image) | `placeholder`, a still |
| content, first frame only | `firstFrame`, a still; the handle is freed |
| content, full | `firstFrame` (a still), then `full` (animated tier) |
| content, spec above 512 px | `firstFrame`, then the same still as `full`; the render is capped at 512 and the handle freed |

Frame 0 is drawn into a temporary native buffer, not an atlas slot (the pool may
be full) and uploaded as premultiplied RGBA. The `full` stage costs the frame
(`w * h * 4`) plus `4 *` the encoded size for the parsed model, as the web client
estimates. A rejected file, an engine error or a frame that does not render ends
in `fail(..., AssetFailureKind.permanent)`; `cancel` stops reporting and frees
whatever the decode already holds. Files with image or text layers still decode;
`LottieInfo.features` is the host's to read.

## Host recipe

The host probes by spawning, and registers only on success:

```dart
try {
  final engine = await IsolateLottieEngine.spawn(); // throws when unavailable
  final scheduler = LottieFrameScheduler(atlas: atlas, clock: clock);
  decoders.register(
    MediaForm.vectorAnimation,
    LottieDecoder(engine: engine, scheduler: scheduler, cache: cache),
  );
} on Object catch (reason) {
  // No decoder (a LottieUnavailable names why): vector animations keep their
  // placeholder. Log it once.
}
```

`atlas` is a `FrameAtlas` over a `LottieFrameRenderer(engine:, memory:,
cache:)` and the one `NativeFramePageMemory`; `cache` is the `FrameCache` below
(`cache:` is optional on both). At shutdown dispose the scheduler, then the
cache (it finishes the writes under way), then close the engine.

## Frame cache

`FrameCache` keeps the **compressed** frames of rendered animations so a second
play, or the next launch, skips the render (ADR 022 "dynamic frame pages", row
Frame cache). It stores opaque bytes: it knows nothing of the codec, the engine
or pixels.

| Type | Role |
| --- | --- |
| `FrameCacheKey` | Content hash, DISPLAY size and engine version. Validated and lower-cased in the constructor (`ArgumentError` for a hash or version with path characters); `toFileStem()` is the file name; `admitted([maxEdge = 512])` tells whether the size is cacheable. |
| `FrameCache` | `open(key)` makes an animation resident and returns its frame count (null: nothing cached; an unadmitted key is always null). `frame` and `has` are synchronous and RAM only. `put(key, index, bytes, frameCount:)` stores one frame, first write wins; when every frame is present the animation is written to disk once, asynchronously. `clear`, `dispose` (finishes pending reads and writes; idempotent). |
| `FrameCacheFiles` | The one place that touches the file system; `FrameCache` takes `directory`, and tests pass a subclass to count or break writes. |

**Tiers.** The RAM tier (default 32 MiB) evicts whole animations, least
recently used first, and never the one being filled when it is the only one.
The disk tier (default 128 MiB) evicts least recently used files after each
write and on the first scan of the directory. Recency is the injected clock;
on disk it is the file's modified time, stamped when the file is written or
opened. `directory: null` keeps memory only.

**File.** `<stem>.frames`, little-endian: magic `FRMC`, format version 1, width,
height, frame count, payload length, payload CRC-32, engine and hash lengths,
the engine version and hash, an offsets table, a lengths table, then the
frames. It is written to `<stem>.<n>.tmp` and renamed, so a crash leaves a temp
file, never a partial entry; the first scan deletes temp files. A file that is
truncated, of another format version or key, with offsets that do not tile the
payload or a wrong CRC is a miss and is deleted, never an exception. The full
layout is documented on `FrameCacheCodec`.

**Failures.** A file-system error (read-only or missing directory, unreadable
file) never fails a render: the first is passed to `onError` (default
`FlutterError.reportError`), later ones are dropped, and after a failed write
the cache stops writing and serves from memory. The directory belongs to one
cache at a time. Web keeps memory only (a later slice).

### In the renderer

`LottieFrameRenderer` is what uses the cache. A job is **cacheable** when its
`LottieSource.cacheKey` is set and admitted and its frame is inside the
animation. For the cacheable jobs of a batch the renderer `open`s each key the
first time it sees it (later batches never wait for the disk), then:

- a frame the cache has is **restored** (`LottieEngine.restore`) and nothing is
  rendered for it;
- every other frame renders through `renderCapturing`, and its compressed
  bytes are `put`;
- a restore that fails (corrupt or wrong-size entry) is rendered after all in
  the same batch, and `FrameCache.invalidate` drops the animation: one damaged
  frame says nothing of how many others are.

The answer lists every job that holds its frame, in job order. Without a cache,
for an uncacheable job, with an engine that has no codec, or with a cache that
was disposed meanwhile, the frame renders as before. There is no cache isolate
([ADR 022](../../docs/adr/022-asset-cache-and-media-pipeline.md)): the render
isolate owns the codec and the file work is asynchronous `dart:io`.

`LottieDecoder(cache:)` names each animation: `FrameCacheKey(contentHash:` the
SHA-256 of the file, `width`/`height:` the size the frames render at,
`engineVersion: LottieNativeVersion.engine)`. A spec above 512 px does not
animate and has no key.

## Fuzzing and benchmarks

The native library is fuzzed in `lottie_native` (see its README). This package
has the playback benchmark, `test/benchmark/lottie_playback_bench_test.dart`:
the real native library in a real render isolate, the scheduler on a manual
clock, the real page uploader, 1, 8 and 32 simultaneous stickers of the
hand-authored fixture at 128 px, 300 ticks after 10 warm-up ticks. It never
fails on a time and is not part of `scripts/bench`; the file is gated by the
`benchmark` tag and by an environment variable, so the unit entrypoint skips it.

```shell
cd packages/lottie_decoder
LOTTIE_PLAYBACK_BENCH=1 flutter test --concurrency 40 test/benchmark/lottie_playback_bench_test.dart
# after an intended change, replace the committed baseline:
LOTTIE_PLAYBACK_BENCH=1 LOTTIE_BENCH_WRITE_BASELINE=1 flutter test --concurrency 40 test/benchmark/lottie_playback_bench_test.dart
```

It prints a table, writes `build/bench/lottie_playback.json` and lists each
metric against `test/benchmark/baseline.json` as a ratio (more than 1.5x for a
time or 1.05x for a count is called worse; nothing fails). Absolute times on a
development machine in debug mode are noisy, so read the shape. The baseline is
the per-metric median of five runs on an Apple-silicon Mac; the first run after
a build is about 2x slower than the rest.

| Stickers | tick (UI isolate) | settled | render round trip | upload | uploaded per tick | pages |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | 0.05 ms | 0.93 ms | 0.17 ms | 0.53 ms | 4 MiB | 1 |
| 8 | 0.05 ms | 0.83 ms | 0.22 ms | 0.38 ms | 4 MiB | 1 |
| 32 | 0.05 ms | 1.10 ms | 0.49 ms | 0.35 ms | 4 MiB | 1 |

What it says. Building and sending the batch costs the UI isolate about 50
microseconds whatever the count. The render isolate round trip grows with the
count (0.17 to 0.49 ms), as it should. The upload does not: every tick uploads
each dirty page in full, so one 1024 px page is 4 MiB per tick for one sticker
or for 32, 64x the 64 KiB that changed at N = 1 and 2x the 2 MiB at N = 32. The
upload time here is the engine's `decodeImageFromPixels` copy and callback in
the headless test engine; it does not include the GPU upload on a device
(frame-timing tools hide that cost too), so the byte count is the finding, not
the 0.4 ms. A partial upload of the changed slots, or a smaller page for a few
stickers, would cut it; that belongs to the frame cache slice.
