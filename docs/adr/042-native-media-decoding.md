# ADR 042: Native media decoding over FFI

Vector-animation stickers (Lottie / TGS) and video GIFs and stickers are
decoded by native engines called through `dart:ffi`, behind the `Decoder` seam
of [ADR 022](022-asset-cache-and-media-pipeline.md). Lottie runs on tlottie
through a thin wrapper crate we own; video runs on a minimal LGPL FFmpeg with
libvpx. On web the same wrapper runs as WebAssembly in JS workers and video
uses the browser's decoder. No platform player is created per message.

**Status**: Accepted  
**Date**: 2026-11-06  
**Amended**: 2026-11-09 (native-media ticket 98): the render isolate reads cached frames from their files (row Workers)  
**Amended**: 2026-11-09 (native-media ticket 110): the render isolates take each texture frame as a request of its own, answered in arrival order, and Lottie renders on a pool of up to four of them (row Workers, section *Amendment: a pool of render isolates*)  
**Relates to**: [ADR 020](020-package-topology.md), [ADR 022](022-asset-cache-and-media-pipeline.md) (page pool and frame cache amendment), [ADR 030](030-testing-policy.md), [ADR 021](021-content-identity-and-collections.md)  

## Context

`MediaForm.vectorAnimation` and `video` exist and no decoder is registered for
either. A chat shows dozens of animated stickers and several GIFs at once, so
the cost per visible item decides whether the list holds its frame rate.

The reference clients agree on the shape: render at display size, never above
512 px; a small fixed number of render threads, never one per item; frames
cached compressed per size and replayed; playback follows visibility; no inline
platform player. None of them isolates the engine from the process.

Facts the decisions rest on:

- **tlottie** (`dkaraush/tlottie`, MIT) is the engine Telegram Desktop ships.
  It is not on crates.io, has a small C API, takes raw JSON (the caller
  gunzips TGS), renders into a caller buffer, and does not render image
  layers, text layers, expressions or effects.
- Telegram's own tlottie web build returns **straight** alpha, while the
  native C API returns **premultiplied**; premultiplying that web output
  matched the native render to within one colour level on every pixel of the
  test corpus (an experiment with that build). The wrapper does not use that
  build: our own crate compiles to WebAssembly and writes the same
  premultiplied bytes as the native build, so nothing converts anywhere. The
  golden `native/tests/golden.rs` / `web/test/golden.test.mjs` holds the host
  build and both wasm builds to one reference frame within one colour level.
- Renders on separate handles in parallel threads match a single-thread
  render frame for frame, and a corpus of malformed inputs (flips,
  truncations, zero bytes, huge sizes, deep nesting) neither crashed nor hung
  under AddressSanitizer; a handle is not shared between threads.
- A native fault in a worker isolate most likely ends the process. Not
  documented; treated as true.
- Build hooks build and run under the pinned Flutter inside this pub
  workspace, and a missing `@Native` symbol throws a catchable
  `ArgumentError`.
- FFmpeg's native VP9 decoder drops alpha; Telegram Desktop forces `libvpx-vp9`.

## Decided

| Area | Decision |
| ---- | -------- |
| Lottie engine | tlottie, pinned by commit, behind **our own thin Rust crate** (the wrapper). The wrapper gunzips TGS, validates a file before tlottie parses it, and exposes a batch render call. The same crate compiles to WebAssembly. rlottie is not kept: an unsupported or invalid file fails to its placeholder. |
| Pixel contract | The wrapper writes **premultiplied** pixels in one documented channel order on every target and states it in its header. The web build is the same crate, so it writes the same premultiplied bytes; the worker converts nothing. A golden with a semi-transparent sticker runs on both builds. |
| Video engine | FFmpeg built `--disable-everything` as **separate shared libraries**: H.264 decoder, decoder-only libvpx VP9 (alpha), `mov` and `matroska` demuxers, swscale; LGPL only, no GPL and no non-free parts, dynamic linking. Output is display-size BGRA. Not folded into the Lottie library. |
| Native source | In this repository. CI builds the native libraries and publishes **hash-pinned prebuilts**; the build hook downloads them. Compiling from source is an opt-in flag, so no host app needs Rust or an NDK by default. **That promise holds only once a manifest with artifacts is published**: until then (`native/prebuilts.json` is committed empty) every build compiles from source or ships no library, and a host without cargo (or without the NDK, for Android) gets no library and a warning. |
| Targets | Android arm64-v8a and x86_64, iOS device and simulator, macOS, Windows, Linux, web. Android libraries are 16 KB page aligned. |
| Workers | A pool of long-lived **render isolates** (one to four, one per core but one by default; *Amendment: a pool of render isolates*) owns the Lottie handles, each handle on the isolate that loaded it, and runs the batch call on the clock's cadence: one batch a tick for the page slots, split by isolate, and one request per texture frame, each isolate answering in arrival order, so a lease waits only for its own frame ([ADR 043](043-platform-texture-frames.md), *Amendment: each lease waits only for its own frame*). There is no cache isolate: the render isolates also compress and decompress frames (each owns a codec), and read a persisted animation's frames from its file one at a time; the UI isolate keeps the cache's index and hands a finished animation's frames to asynchronous file writes, never a whole file or a checksum pass ([ADR 022](022-asset-cache-and-media-pipeline.md), *Amendment: frames read from the file*). Video decodes on its own workers with a fixed small pool. Hot calls are `@Native(isLeaf: true)` where the native function neither blocks long nor calls back. |
| Hardening | The wrapper checks every file before parsing: encoded size, dimensions, layer and nesting counts, a scan for features tlottie does not render, and frame-count and memory caps. A file that fails the check ends in `AssetProgress.fail`. The wrapper is fuzzed. There is no sandbox process: a native fault ends the app, so the check and the fuzz are the defence. |
| Load failure | Each native package exposes a guarded probe (one cheap call). For Lottie the host's probe is `IsolateLottieEngine.spawn`: it starts the render isolate, which runs the binding probe, and throws `LottieUnavailable` with the reason when the library is missing or speaks another ABI version (any other failure to start surfaces as it happened). The host registers the decoder only if it passes, logging once through a diagnostics callback. Without a decoder the form stays at its placeholder ([ADR 022](022-asset-cache-and-media-pipeline.md)). Nothing retries in-process. |
| Packages | Two pairs, per [ADR 020](020-package-topology.md): `lottie_native` and `lottie_decoder`, `video_native` and `video_decoder`. A `*_native` package is a leaf holding the crate or recipe, the build hook and the bindings, native and web behind a conditional import; a `*_decoder` package holds the `Decoder` adapter and the isolate protocol. The page pool and the renderer seam live in `catalog_assets`. |
| Web, Lottie | The wrapper as WebAssembly (SIMD and no-SIMD builds, chosen by a `WebAssembly.validate` probe) in a module worker shipped in `web/`. The Dart seam is `LottieEngine`, which returns pixels (`renderPixels`); `WebWorkerLottieEngine` implements it over the worker, and `PixelCopyFrameRenderer` copies each result into the page (page memory a Dart list). Writing to a native address is `LottieSlotEngine`, which only the in-process and isolate engines are, so the zero-copy `LottieFrameRenderer` stays native. |
| Web, video | Hidden `<video>` elements with `requestVideoFrameCallback`; frames are copied into the same page slots. No WebCodecs in the first build. A browser without WebM alpha shows the first-frame still. |
| Web, cache | Memory only, bounded by the same byte budget. No IndexedDB. |
| Out of scope | Hardware video decode, the full-screen viewer's player, the pure-Dart `lottie` package as a fallback. |

## Why

- One wrapper with one batch call keeps the FFI boundary coarse: one call per
  tick renders every active slot, not one call per sticker per frame. Parsing
  and gunzip run natively and the same code runs on web.
- Owning the wrapper isolates the application from tlottie's API and gives the
  checks and the pixel contract one home. tlottie is single-maintainer and
  four months old, so pinning by commit and checking input are the controls.
- Separate FFmpeg libraries keep the LGPL relinking position clean and let
  video and Lottie ship on their own cycles.
- Prebuilts keep Rust and the NDK off every contributor's and host's machine.
- Display-size rendering and per-size caching follow the reference clients;
  at 60 fps and 180 frames a 512 px sticker is about 180 MiB raw but about
  18 MiB at a 160 px display size.

## Rejected

| Alternative | Why not |
| ----------- | ------- |
| Bind `tlottie.h` directly | Gunzip and validation move to Dart, calls stay per animation, and web needs a second story |
| `dotlottie-flutter` | Widget player with its own render loop and texture; mobile is not FFI; conflicts with the shared clock |
| rlottie as engine or fallback | Maintenance mode; two engines to pin and test; the reference desktop client moved off it |
| Pure-Dart `lottie` as fallback | Not selected; web uses the worker |
| One native library with static FFmpeg | LGPL grey area, and couples the release cycles |
| Platform video players inline | A decoder instance and a texture per message; limits and black frames while scrolling |
| WebCodecs first on web | Neither reference web client uses it; needs a demuxer and has support gaps |
| Out-of-process parsing | Not possible on iOS, costly on Android |
| `native_toolchain_rust` in the hook | Puts rustup on every machine that builds |

## Open and unverified

Settled before the corresponding package lands, as the first implementation
tickets:

- The native build on targets other than macOS arm64 (built and checked there;
  needs Rust on iOS, Android, Windows and Linux CI).
- The original 269-byte malformed file and a coverage-guided fuzz run; the
  checks above are a fixed corpus, not a proof.
- Thread safety beyond one handle per thread: a handle shared between threads
  at once was not tested and is not allowed (the pool pins each handle to one
  isolate). Different handles on different threads are verified
  (*Amendment: a pool of render isolates*).
- The offline build and a macOS profile build of a hook package.
- The Apple store and LGPL relink rules, per-ABI FFmpeg sizes, the H.264
  patent position. The last is a decision for the product owner, not code.
- Whether the Invert and Layer Control effects change a render the engine
  ignores (native and wasm agree with each other, which says nothing about a
  reference render).

## Related

- Glossary: [Content and assets](../content/CONTEXT.md)
- Pause policies the playback clock already applies: [ADR 022](022-asset-cache-and-media-pipeline.md) amendments

## Amendment: a pool of render isolates

Native-media ticket 110. With one render isolate every Lottie frame of a
screen queued on it: once each lease waited only for its own frame
([ADR 043](043-platform-texture-frames.md), *Amendment: each lease waits only
for its own frame*), the chat's sticker queued behind a panel's dozen cells
and played at about 30 changes a second (device recording, frame gaps p50
33 ms, against 24 ms before and 17 ms with the panel closed). The reference
client renders each animation on a pool of four threads.

| Area | Decision |
| ---- | -------- |
| Contract | The wrapper's: a handle is used by one thread at a time; different handles may render on different threads at once (`chat_lottie.h`). Evidence below. |
| Pool | `IsolateLottieEngine.spawn(workers:)`, one to four isolates; `defaultWorkers` is the core count less one, at most four. Each isolate has its own binding, codec, file reader and texture calls. |
| Placement | A handle stays on the isolate that loaded it (the fewest handles at the load), so every request naming it runs in the order sent; the handle id the engine gives out encodes the isolate (`local * workers + index`). A request over handles of several isolates is split, one request to each, and answered in job order once all answered. A restore names no handle and goes to the isolate with the fewest requests waiting; a lease has one frame out at a time, so where its restore runs does not reorder its frames. |
| Cache | Frames of a persisted animation are read from the file by whichever isolate restores them; each reader keeps its own open files (64 per isolate). Writes and the index stay on the UI isolate (*Amendment: frames read from the file* in ADR 022), unchanged. |
| Priority | Of the texture writes of a tick, the largest frame is sent first, so the surface in front (a chat sticker) is ahead of the small cells queued on the same isolate. |
| Failure | One isolate ending closes the engine: its handles are gone, and the others finish what they were sent and shut down. |
| Host | The example starts `defaultWorkers`; the `LOTTIE_WORKERS` define (1 to 4) picks the size for a comparison. |

Evidence for the contract (2026-11-09, wrapper `chat_lottie` over tlottie
rev `92df98dc20`):

- The wrapper keeps no state outside a handle: `ChatLottie` is one
  `CPURenderer`; `chat_lottie_render_batch` makes its scratch buffer per call;
  the frame codec (`lz4_flex`, safe encode and decode) has no globals.
- tlottie's process-wide state is read-only after first use and thread safe:
  `OnceLock` caches of CPU features and an environment budget override, and
  atomic CPU-feature caches. Interior mutability (`Cell`, `RefCell`, `Rc`) is
  local to one parse or one render's budget. The renderer's pointer to the
  caller's buffer lives for one render and is cleared after it.
- Tests: `two_handles_on_two_threads_match_serial_output` and
  `four_threads_load_render_and_restore_their_own_handles_at_once`
  (`packages/lottie_native/native/tests/render.rs`): four threads load,
  render, compress and restore their own handles at once and match one
  thread byte for byte. On the Dart side the engine contract suite, the
  texture writes and a disk-persisted restore run over a pool of isolates
  against the native library.
- Not shown: one handle on two threads at once (not allowed), and the
  sanitizers (no ThreadSanitizer run on the wrapper).
