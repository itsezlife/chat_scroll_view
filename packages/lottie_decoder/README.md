# lottie_decoder

The Lottie adapter for the frame pool
([ADR 042](../../docs/adr/042-native-media-decoding.md), ADR 022 "dynamic frame
pages"): an async engine seam over a `lottie_native` binding, native page
memory a render isolate can write, and a `FrameRenderer` that draws into it.

`package:lottie_decoder/lottie_decoder.dart` compiles for the web: the neutral
files are exported plainly, and the files that need `dart:ffi`, `dart:io` or
`dart:isolate` (`LottieSlotEngine`, the two engines, `NativeFramePageMemory`,
`LottieFrameRenderer`, `DirectoryFrameCacheFiles`, `LottieContentHashWorker`)
only where they exist, as in
`lottie_native`.

## Types

| Type | Role |
| --- | --- |
| `LottieEngine` | The neutral, pixel-returning face of a renderer, and the only engine the decoder, the scheduler and the paintables know: `load`, `renderPixels` (of `LottiePixelJob`; one `LottiePixels` per job, tightly packed premultiplied RGBA of exactly `width * height * 4` bytes, or null for a job that did not render; never throws for one bad job), `dispose`, `close` (idempotent; requests already made run to completion first, for at most the engine's `closeTimeout`, 10 s by default, after which the isolate or worker is ended and what is pending fails with `LottieEngineClosed`; later calls throw `LottieEngineClosed`, a `StateError`). Compiles for the web. |
| `LottieSlotEngine` | A `LottieEngine` that also draws into native memory by address (native only): `renderBatch` (of `LottieEngineJob`), `renderCapturing` (the same, and each rendered slot comes back compressed as a `LottieCapture`), `restore` (decompress `LottieRestoreJob`s into slots: `ok`, or `failed` with the slot untouched). |
| `InProcessLottieEngine` | A `LottieSlotEngine` that runs a binding on the calling isolate, and a `LottieFrameCodec` if given one. `renderPixels` renders into a temporary native buffer and copies out. With `FakeLottieBinding` it is the engine fake. |
| `IsolateLottieEngine` | A `LottieSlotEngine` on one long-lived render isolate that owns the binding and every handle. `spawn({bindingFactory, codecFactory})` builds the binding and the frame codec inside the isolate (the codec only if the binding is available, and dropped if it is not; compressed bytes and pixels cross as `TransferableTypedData`) and throws a `LottieUnavailable` (a `StateError`) carrying the `LottieAvailability` when the binding is unavailable; any other start-up failure surfaces as it happened, and the isolate and ports are released. One request failing throws a `RemoteError` and spares the engine; the isolate ending fails every pending request with `LottieEngineClosed` and closes the engine. Requests run in arrival order. A native fault ends the process and cannot be caught. |
| `LottieEngineContract`, `LottieSlotEngineContract` (`testing.dart`) | The behaviour every engine shares (the first), and every slot engine adds (the second), run over the in-process engine and the isolate engine on the fake and on the real binding, and over `FakePixelLottieEngine`. |
| `FakePixelLottieEngine` (`testing.dart`) | A pixel-only `LottieEngine` (no slot method) whose pixel at column x, row y of frame f is `[x, y, f, 255]`, so a misplaced copy shows. |
| `NativeFramePageMemory` | `FramePageMemory` in `calloc`ed memory (a Dart-heap list cannot be written from another isolate). `page(i, side:)`, `sideOf(i)`, `addressOf(i, side:)`, `drop`, `dispose`; each page has the side of its slot. |
| `LottieFrameScheduler` | The one owner of the host's `FrameAtlas`: follows `PlaybackClock` while a lease exists, renders the wanted frames as one batch per tick, and frees a slot after one to two idle periods (default 1 s) by a single sweep timer. The sweep uses a real `Timer` by design: it keeps counting while the clock is paused, and a repaint after a long pause reacquires the entry and draws the last rendered frame, not the still. |
| `LottieFrameSize` | The one render size (`fitting(info, edge)`) the decoder and the paintable share. |
| `LottieAnimationPaintable` / `LottieStillPaintable` | The animation (pull-driven, one scheduler key per animation, `onDispose` frees its handle) and a decoded still. |
| `LottieDecoder` | The `Decoder` for `MediaForm.vectorAnimation`, built from an engine, the scheduler and two injectable image steps (`decodeImage`, `uploadPixels`). |
| `LottieSource` | A frame job's `source`: the `LottieHandle`, the animation's frame count and its `FrameCacheKey?`. |
| `LottieFrameRenderer` | `FrameRenderer` over a `LottieSlotEngine`, one `NativeFramePageMemory` and an optional `FrameCache`; zero-copy and native only. A job's `source` is a `LottieSource`. |
| `PixelCopyFrameRenderer` | `FrameRenderer` over any `LottieEngine`: one `renderPixels` per batch, then each result's rows copied into any `FramePageMemory` at the slot offset (`ListFramePageMemory` on the web). No frame cache: web v1 is memory only. Compiles for the web. |
| `WebWorkerLottieEngine` | The web's `LottieEngine`: `spawn(port, {wasmUrl, wasmNoSimdUrl, readyTimeout})` over a `LottieWorkerPort`. Neutral Dart (it runs on the VM in tests). Posts `init`, waits for `ready` (10 s by default) and throws a `LottieUnavailable` (`missingLibrary`, with the worker's reason) on `unavailable`, on a worker failure before ready, or on a timeout, terminating the worker. Requests are posted at once in call order (a `renderPixels` over `maxJobsPerRequest`, 256, jobs is several requests), each under an `id`, and replies are matched by `id` (the worker serves them in order, the engine does not rely on it). A load status maps to a `LottieRejection` as in the native binding; a render result whose buffer is not `width * height * 4` bytes is a null job. An `ok: false` reply fails that request only (`LottieWorkerError`); the worker failing or dying fails every pending request with `LottieEngineClosed('the worker ended')` and closes the engine. |
| `LottieWorkerPort` | The host's end of a Lottie worker: `post`, `messages`, `failures`, `terminate`. The seam between the protocol and what carries it. |
| `JsLottieWorkerPort`, `JsLottieWorker.spawnFromUrls` | The browser implementation over `package:web` (a module `Worker`), and the one call that starts it and the engine. Exported by `package:lottie_decoder/web.dart`, which only a web build imports. |
| `FakeLottieWorker` (`testing.dart`) | The worker side of the protocol in memory, over a `FakePixelLottieEngine`, with knobs to hold and reorder replies, fail a request, send a short buffer, stay silent, report `unavailable` or die. |
| `CountingLottieEngine` (`testing.dart`) | Forwards to an engine and counts the jobs rendered and restored, for "this pass rendered nothing". |

## Web

`WebWorkerLottieEngine` is the `LottieEngine` of the web: WebAssembly in a
module worker draws the frames and transfers the pixels back, and
`PixelCopyFrameRenderer` copies them into page memory
([ADR 042](../../docs/adr/042-native-media-decoding.md), "Web, Lottie"). The
protocol is documented at the top of `chat_lottie_worker.js` in
`lottie_native/web`; the engine mirrors it and a status test parses
`chat_lottie.h` so a number cannot drift.

```dart
import 'package:lottie_decoder/web.dart'; // a web build only

final engine = await JsLottieWorker.spawnFromUrls(
  workerUrl: Uri.parse('lottie/chat_lottie_worker.js'),
  wasmUrl: Uri.parse('lottie/chat_lottie.wasm'),
  wasmNoSimdUrl: Uri.parse('lottie/chat_lottie.nosimd.wasm'),
); // throws LottieUnavailable: register no Lottie decoder then
```

Hand that engine to `LottieDecoder` and `PixelCopyFrameRenderer` as any other.
The worker, its `chat_lottie_core.mjs` (which must sit beside it) and the two
wasm builds come from `dart native/tool/build_web.dart` of `lottie_native`;
where a host serves them from is not decided yet. Relative urls resolve
against the page.

What has run in a browser: see "Not run" under Web in
[host integration](../../docs/host-integration.md).

## Host contract

| The host provides | The host must not |
| --- | --- |
| An engine over an available binding (a `LottieSlotEngine` for `LottieFrameRenderer`, any `LottieEngine` for `PixelCopyFrameRenderer`), and the one `NativeFramePageMemory` the renderer and the pool share | Pass the renderer another memory (`StateError`) or a job whose `source` is not a `LottieSource` (`ArgumentError`) |
| `dispose` for each loaded handle and `close` for the engine | Use a view from `page` after `drop` or `dispose` |
| `dispose` for the `FrameCache`, before `close` for the engine | Give one cache directory to two caches |

## The decoder

| Request | Reports |
| --- | --- |
| thumbnail (an ordinary image) | `placeholder`, a still |
| content, first frame only | `firstFrame`, a still; the handle is freed |
| content, full | `firstFrame` (a still), then `full` (animated tier) |
| content, spec above 512 px | as full, rendered at 512 px on the longer side; the surface scales it up |

Frame 0 is drawn through `renderPixels`, not into an atlas slot (the pool may
be full) and uploaded as premultiplied RGBA. A `FetchedFile` is read with
`dart:io`; on the web it fails the decode (`UnsupportedError`). The `full` stage costs the frame
(`w * h * 4`) plus `4 *` the encoded size for the parsed model. A rejected file, an engine error or a frame that does not render ends
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
| `FrameCacheKey` | Content hash, DISPLAY size and engine version. Validated and lower-cased in the constructor (`ArgumentError` for a hash or version with path characters); `toFileStem(parity)` is the file name of one parity (`FrameParity.even` or `odd`); `admitted([maxEdge = 512])` tells whether the size is cacheable. |
| `FrameCache` | `open(key)` lists the directory once and answers whether anything is cached for the key (false for an unadmitted key); it reads no frame. `frame` answers synchronously where a frame is: a `CachedFrameBytes` while its animation is in RAM, a `CachedFrameFile` (path, key, index) once it is on disk, which the engine reads on its own isolate. `put(key, index, bytes, frameCount:)` stores one frame, first write wins. An animation is two fills, its even frames and its odd frames: when every frame of one parity is present that parity is written to disk once, as its own file, asynchronously, and then leaves RAM. A playback at half rate asks only for the even frames, so its fill completes over one pass; a playback at full rate later restores those and fills the odd ones. `residentBytes`, `invalidate`, `clear`, `dispose` (finishes pending writes; idempotent). |
| `FrameCacheFiles` | The interface of the one place that touches the file system. `DirectoryFrameCacheFiles` (native) is the implementation `FrameCache(directoryPath:)` opens through the `$openFrameCacheFiles` hook of `src/environment_specific/` (the VM file by default, the JS file on the web); tests pass a subclass to count or break writes. The web's hook refuses a path with an `ArgumentError`. |

**Tiers.** The RAM tier (default 32 MiB) holds the fills under way (with no
directory, the complete ones too) and evicts whole fills, one parity of an
animation each: first
those unused for `playingFor` (default 2 s), least recently used first, then,
when all left play, the one that started filling last, never the oldest. A
dropped animation renders as without a cache until there is room; nothing is
reloaded. The disk tier (default 128 MiB, or none) evicts least recently used
files after each write and on the first scan of the directory. Recency is the
injected clock; on disk it is the file's modified time, stamped when the file
is written or opened and at most every 30 s while it serves frames.
`directoryPath: null` keeps memory only.

**File.** `<stem>.frames`, one per parity of an animation, little-endian: magic
`FRMC`, format version 3, width, height, frame count (of the parity), payload
length, engine and hash lengths, the parity, the engine version and hash, an
offsets table, a lengths table, then the frames (no
checksum: the frame codec's exact-size decode catches a damaged frame). It is
written as the header and then the frames, to `<stem>.<n>.tmp`, and renamed, so
a crash leaves a temp file, never a partial entry; the first scan deletes temp
files. The engine's `FrameFileReader` reads the header once per open file and
then one frame at a time; a file that is missing, truncated, of another format
version (versions 1 and 2 included), key or parity, or whose offsets do not tile the payload
serves no frame, and the renderer's invalidate deletes it. The full layout is
documented on `FrameCacheCodec`.

**Failures.** A file-system error (read-only or missing directory, unreadable
file) never fails a render: the first is passed to `onError` (default
`FlutterError.reportError`), later ones are dropped, and after a failed write
the cache stops writing and serves from memory. The directory belongs to one
cache at a time. The web keeps memory only: `directoryPath` must be null there.

### In the renderer

`LottieFrameRenderer` is what uses the cache. A job is **cacheable** when its
`LottieSource.cacheKey` is set and admitted and its frame is inside the
animation. For the cacheable jobs of a batch the renderer `open`s each key the
first time it sees it (later batches never wait for the disk), then:

- a frame the cache has is **restored** (`LottieSlotEngine.restore`, or a
  restore into a texture) and nothing is rendered for it; a persisted frame is
  read from its file on the engine's isolate, so only its name crosses;
- every other frame renders through `renderCapturing`, and its compressed
  bytes are `put`;
- a restore that fails (corrupt or wrong-size entry) is rendered after all in
  the same batch, and `FrameCache.invalidate` drops the animation: one damaged
  frame says nothing of how many others are.

The answer lists every job that holds its frame, in job order. Without a cache,
for an uncacheable job, with an engine that has no codec, or with a cache that
was disposed meanwhile, the frame renders as before. There is no cache isolate
([ADR 022](../../docs/adr/022-asset-cache-and-media-pipeline.md), *frames read
from the file*): the render isolate owns the codec and reads the cached frames
it restores; the UI isolate keeps the index and hands a finished animation's
frames to asynchronous `dart:io` writes.

`LottieDecoder(cache:)` names each animation: `FrameCacheKey(contentHash:` the
SHA-256 of the file, `width`/`height:` the size the frames render at,
`engineVersion: LottieNativeVersion.engine)`. A spec above 512 px renders,
and is keyed, at 512.

The hash runs off the UI isolate. By default every decoder shares one
long-lived worker isolate, `LottieContentHashWorker.shared`, spawned at the
first hash and never closed; it hashes one file at a time. A host that wants
its own lifetime passes `hashContent: worker.hash` and closes the worker
itself. On the web the hash runs on the calling thread.

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
| 1 | 0.04 ms | 0.58 ms | 0.12 ms | 0.33 ms | 256 KiB | 1 |
| 8 | 0.04 ms | 0.67 ms | 0.18 ms | 0.31 ms | 512 KiB | 2 |
| 32 | 0.04 ms | 1.33 ms | 0.38 ms | 0.77 ms | 2 MiB | 8 |

What it says. Building and sending the batch costs the UI isolate about 40
microseconds whatever the count. The render isolate round trip grows with the
count (0.12 to 0.38 ms), as it should. A page is uploaded whole
(`decodeImageFromPixels` has no partial update), so the page size is what a
changed frame costs. Pages are sized by class (twice the class edge: 256 px for
the 128 px stickers here), so one sticker uploads 256 KiB, 4x the 64 KiB that
changed, and eight or more upload exactly what changed. Before this change every
class shared a 1024 px page: 4 MiB per tick for one sticker or for 32, 64x the
bytes that changed at N = 1 (see the amendment in ADR 022). The price shows at
N = 32: eight uploads of 256 KiB take 0.77 ms where one 4 MiB upload took 0.35 ms
in the headless engine, so the per-call cost matters more than the bytes there.
That upload time is the engine's `decodeImageFromPixels` copy and callback in
the headless test engine; it does not include the GPU upload on a device
(frame-timing tools hide that cost too), so the byte count is the finding, not
the milliseconds.
