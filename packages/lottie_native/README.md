# lottie_native

The binding interface to the native Lottie renderer (tlottie behind a batch C
API, [ADR 042](../../docs/adr/042-native-media-decoding.md)): load a file,
render frames into page memory, dispose. A leaf of the workspace
([ADR 020](../../docs/adr/020-package-topology.md), rule 8): it depends on no
workspace package and is reached through its decoder only.

This package holds the whole native surface of Lottie: the binding interface
(`LottieBinding`), the fake and the contract suite (`testing.dart`), the
native binding (`NativeLottieBinding`) with the frame codec
(`LottieFrameCodec`, lz4 over page memory) and `LottieNativeVersion`, the
build hook that delivers the compiled library (from source or as a
hash-pinned prebuilt, `native/prebuilts.json`), and the web side: the same
crate as WebAssembly with its JavaScript core and worker (`web/`).

## Native library delivery

**No prebuilt library is published yet: `native/prebuilts.json` is committed
empty (no `baseUrl`, no artifacts), so every build today compiles from
source.** The machinery below is in place for when the maintainer publishes.

`hook/build.dart` gets the library in this order, first match wins:

1. **Compile from source** when `build_from_source` is on: the app's pubspec
   sets it for this package, or the environment variable
   `LOTTIE_NATIVE_BUILD_FROM_SOURCE=1` is set.

   ```yaml
   # the app's pubspec.yaml
   hooks:
     user_defines:
       lottie_native:
         build_from_source: true
   ```

   Either switches it on; neither switches the other off. Hooks cannot track
   the environment, so after changing the variable run `flutter clean` (or
   touch `native/prebuilts.json`) to re-run the hook. With the flag on a
   missing `cargo` or an uncompilable target fails the build.
2. **Download the prebuilt** when the manifest has an artifact for the build's
   target key, its `sourceHash` equals the hash of the `native/` sources in
   this package, and `baseUrl` is set. The file is fetched into the hook's
   shared output directory at `<sha256>/<file>` (every consumer reuses it),
   checked for size and SHA-256, and refused on any mismatch. A verified
   cached file is reused with no network. A failed download (network, HTTP
   status, 60 s timeout) is logged, never fatal.
3. **Compile from source** when this host builds the target (table below)
   and `cargo` is found; otherwise **no asset** and a warning that names the
   target and points at the prebuilt route: the build succeeds and
   `NativeLottieBinding.probe()` reports `missingLibrary`. The same holds
   for an Android target when no NDK is found, unless the flag is on, which
   fails the build with the NDK message.

`cargo` is found on `PATH`, then under `CARGO_HOME`, then in `~/.cargo/bin`;
without Rust and with the flag on, the build fails and says to install it from
[rustup.rs](https://rustup.rs). When cargo fails for a missing Rust target the
message ends with the `rustup target add` line. A first source build needs
network for the crates and the pinned tlottie commit.

### Targets and where they build

| Target key | Rust triple | Built from source on |
| --- | --- | --- |
| `macos-arm64`, `macos-x64` | `aarch64-apple-darwin`, `x86_64-apple-darwin` | a Mac |
| `ios-arm64` | `aarch64-apple-ios` | a Mac |
| `ios-arm64-simulator`, `ios-x64-simulator` | `aarch64-apple-ios-sim`, `x86_64-apple-ios` | a Mac |
| `android-arm64`, `android-x64` | `aarch64-linux-android`, `x86_64-linux-android` | macOS, Linux or Windows, with the NDK |
| `linux-x64`, `linux-arm64` | `x86_64-unknown-linux-gnu`, `aarch64-unknown-linux-gnu` | Linux of the same architecture; another architecture only when the app sets `CARGO_TARGET_<TRIPLE>_LINKER` |
| `windows-x64` | `x86_64-pc-windows-msvc` | Windows |

Android 32-bit ARM is not supported (ADR 042): it gets no asset. Web has no
native library. The Linux and Windows builds are not compiled by this
repository's checks yet.

A from-source build needs on the host: `cargo` and the Rust target
(`rustup target add <triple>`; the hook never installs anything), Xcode for
Apple targets, and the NDK for Android. iOS builds pass the hook's iOS
deployment target as `IPHONEOS_DEPLOYMENT_TARGET`.

**Android NDK discovery**, first match wins: `ANDROID_NDK_HOME`, then
`ANDROID_NDK_ROOT`, then the highest version (compared as numbers) under
`<sdk>/ndk`, where `<sdk>` is `ANDROID_HOME`, else `ANDROID_SDK_ROOT`, else
the Android Studio default (`~/Library/Android/sdk`, `~/Android/Sdk`,
`%LOCALAPPDATA%\Android\Sdk`). A folder counts only if it holds the host's
`toolchains/llvm/prebuilt/<host>` directory. The linker is the NDK's
`<triple><api>-clang` for the app's Android API level (the nearest level the
NDK offers; below its lowest, the lowest), set through
`CARGO_TARGET_<TRIPLE>_LINKER` and `_AR`.

**16 KB pages.** Every Android build adds `-C
link-arg=-Wl,-z,max-page-size=16384`, appended to the flags the app set in
`CARGO_ENCODED_RUSTFLAGS` or `RUSTFLAGS` (these are carried over, but cargo
ignores `rustflags` from `.cargo/config.toml` once either variable is set).
After each Android build the hook reads the ELF program headers and fails
the build if the machine is not the target's or any `PT_LOAD` segment is
aligned below 0x4000; after an Apple build it checks the Mach-O CPU. A
downloaded prebuilt passes the same check (machine or CPU, and 16 KB segments
on Android; the ELF machine on Linux, the PE machine on Windows) before it is
used, because its hash only says it is the file the manifest names: a failing
file is deleted and treated as no prebuilt, and the hook goes on to compile.

**Android API level.** The hook links for the app's Android API level (the
`<triple><api>-clang` above). The published prebuilts are built at API 21,
Flutter's minimum, so one library loads on every supported device.

**Cross-compile smoke.** `LOTTIE_NATIVE_CROSS=1 flutter test --concurrency 40
test/unit_test.dart --plain-name cross-compile` compiles the crate for each
Apple and Android target through the hook's own build function (compile only;
nothing is launched). A target whose host, Rust target or NDK is missing is
skipped with the reason.

The hook declares every file under `native/src/` and `native/include/`,
`Cargo.toml`, `Cargo.lock`, `prebuilts.json` and its own Dart sources as
dependencies, so editing any of them re-runs it.

### The manifest

`native/prebuilts.json`, schema 1 (unknown keys are ignored):

```json
{
  "schema": 1,
  "crateVersion": "0.1.0",
  "sourceHash": "<64 hex: sha256 of the sources, see below>",
  "baseUrl": "https://host.example/lottie_native/0.1.0/",
  "artifacts": {
    "macos-arm64": {
      "file": "libchat_lottie-macos-arm64.dylib",
      "sha256": "<64 hex>",
      "size": 1234567
    }
  }
}
```

- Target keys: `macos-arm64`, `macos-x64`, `ios-arm64`,
  `ios-arm64-simulator`, `ios-x64-simulator`, `android-arm64`, `android-x64`,
  `linux-x64`, `linux-arm64`, `windows-x64`.
- `baseUrl` is empty or an absolute `https` URL ending with `/`; `file` is a
  bare file name of letters, digits, `.`, `_` and `-` (no leading dot, no
  `..`), percent-encoded and appended to it. A redirect is followed only to
  another `https` URL. Hex values are lower case.
- An empty `baseUrl` or `artifacts` means "no prebuilt", never an error. A
  manifest that does not parse is ignored with a warning.
- `sourceHash` is the SHA-256 over this listing: the line
  `lottie-native-source-v2` and LF, then the files `Cargo.toml`, `Cargo.lock`,
  everything under `include/` and everything under `src/` (all in `native/`),
  sorted by `/`-separated relative path, each as
  `<byte length of the path>:<path><byte length of the content>:<content>`
  (ASCII decimal lengths, bytes counted after UTF-8, no other separator).
  Every field announces its own length, so a path cannot imitate the framing
  of the record after it; the first format (`<path> LF <length> LF <bytes>
  LF`) could be fooled that way and is gone. A path with a control character
  is an error. Bytes are hashed as stored, so a checkout that rewrites line
  endings falls back to compiling.

### Publishing prebuilts (maintainer)

> The two workflows (`lottie_native_prebuilts.yml`,
> `lottie_native_check.yml`) are UNTESTED on GitHub: they were written
> without a hosted runner and only their YAML was parsed. Expect to fix them
> on first use.

**Open decision: where the binaries are hosted.** The workflow assumes the
GitHub Releases of this repository (`baseUrl` is
`https://github.com/<owner>/<repo>/releases/download/<tag>/`). A release is
immutable in practice and the manifest pins every file's SHA-256, so the host
is not trusted, but a private repository needs another host or a token, and
another host means another `--base-url`.

Steps:

1. Make the crate final: edit, commit and merge it. Bump `version` in
   `native/Cargo.toml` if the libraries should get a new tag (the tag must be
   `lottie_native-v<Cargo version>`; the workflow refuses a tag that
   disagrees).
2. Push the tag `lottie_native-v<version>` (or run the workflow by hand on
   that tag). The workflow builds all ten target keys with
   `cargo build --release --locked`, then one job assembles `prebuilts.json`
   with `--require-all`: every library is held to the hook's own header check
   for its target (`native/tool/verify_artifact.dart` is the same check on one
   file), so a missing, empty, duplicated, mislabelled, wrong-CPU or 4 KB-aligned
   Android library fails the run before anything is published. The release job
   then creates the GitHub Release with the libraries and the manifest
   attached. Run by hand from a branch it builds and assembles but publishes
   nothing.
3. Review the release: ten libraries, `prebuilts.json`. The manifest is also
   the workflow artifact `prebuilts-manifest`.
4. Copy that `prebuilts.json` over `native/prebuilts.json` and open a pull
   request. The workflow never commits. `native check` runs
   `dart native/tool/source_hash.dart --check` on it.
5. Merge. From then on a consumer downloads the prebuilt for its target while
   `sourceHash` equals the hash of the sources it has.

By hand (any machine, same result): put the built files, named
`libchat_lottie-<key>.<so|dylib|dll>`, alone in a directory and run, from the
package root,

```sh
dart native/tool/assemble_manifest.dart <dir> --base-url <https url ending /> \
  --require-all
dart native/tool/verify_artifact.dart <file> <key>   # prints OK or the problem
```

It writes `native/prebuilts.json` (or `--out <file>`): each artifact's
`file`, `sha256` and `size`, the current `sourceHash` and `crateVersion`. It
writes nothing if a file is empty, fails the hook's header check for its key
(the format, the CPU, and 16 KB segments on Android), two files claim one key,
or a required key has none (`--require-all` requires every key the hook
knows; `--require a,b` names some), and it re-reads what it wrote.
`manifest_entry.dart` prints one entry; `source_hash.dart` prints the hash,
`--write` records it, `--check` exits non-zero when a non-empty recorded
`sourceHash` differs from the sources. (Use `dart <file>`, not `dart run`,
which would run the build hook.)

**What CI repeats from the hook.** The prebuilts workflow spells out the
per-target build commands (`cargo build --release --locked --target`, the
Android linker, `-Wl,-z,max-page-size=16384`) instead of calling the hook's
builder, because that builder (`compileCrate`) is reached through a Flutter
build with a hook input, and a leg that only needs cargo should not need
Flutter to build. The duplication is the Android linker setup and the build
flags; the assemble job catches a drift (a wrong machine, 4 KB pages) before
anything is published, though it reports it after the build legs, not at the
end of the leg that drifted. Only the assemble job needs Flutter and the md
fork checked out, to resolve the workspace. Actions are pinned to major tags
(`actions/checkout@v4`), not commit SHAs, on purpose: only first-party
actions and `subosito/flutter-action` are used, and the one job with a write
permission runs no third-party code.

**When the crate changes**, `--check` fails the pull request until the
manifest agrees with the sources: publish new libraries (steps 1 to 5), or
withdraw the old ones on purpose by setting `sourceHash` to `""` and
`artifacts` to `{}`. Until new libraries are published, a stale `sourceHash`
already disables the old artifacts at build time; the check is what stops it
from lingering unnoticed. While `artifacts` is empty, `source_hash.dart
--write` alone satisfies it.

## Web build

On web the same crate runs as WebAssembly in plain JavaScript workers
([ADR 042](../../docs/adr/042-native-media-decoding.md)). The files live in
`web/`; **the built `.wasm` files are not committed**. Build them with:

```sh
dart native/tool/build_web.dart --out packages/lottie_native/web/dist
```

(`web/dist/` is git-ignored.) The tool runs cargo twice for
`wasm32-unknown-unknown` and writes, into the output directory:

| File | What |
| --- | --- |
| `chat_lottie.wasm` | built with `-C target-feature=+simd128` |
| `chat_lottie.nosimd.wasm` | plain wasm32, for runtimes that cannot validate SIMD |
| `chat_lottie_core.mjs` | `createChatLottie(wasmBytes)`: `load`, `renderPixels`, `dispose`, `close`; no DOM |
| `chat_lottie_worker.js` | the module worker; protocol at the top of the file |

Both builds need `cargo` and `rustup target add wasm32-unknown-unknown`; the
tool never installs anything and says so when either is missing. It clears
`RUSTFLAGS` and `CARGO_ENCODED_RUSTFLAGS` so the plain build is plain.
Serve the four files from one directory (the worker imports the core by
relative path); the host sends `{type: 'init', wasmUrl, wasmNoSimdUrl}` and
the worker picks the build with a `WebAssembly.validate` probe. At most
`min(4, hardwareConcurrency)` workers are meant to run (ADR 042).

The module exports the C ABI plus `chat_lottie_alloc` / `chat_lottie_dealloc`
(wasm32 only, in `chat_lottie.h`): JavaScript cannot write into module memory
without owning a region of it. Pixels come out as the header says everywhere,
premultiplied `[R, G, B, A]`, tightly packed, one `Uint8Array` copy per job,
transferred to the host.

**Handles, limits and traps.** A `handle` in the worker protocol is an opaque
id (1, 2, 3, ...), never an address in the module, and an id is never
reissued, so a stale handle fails with `-1` and cannot reach a later
animation. The worker drops a message that is not an object with a string
`type` and (but for `init`) an integer `id` with one `{type: 'error'}` reply,
closes the previous core on a second `init`, and refuses a request over the
caps: at most 256 jobs, integer edges 1 to 512 and a finite frame, and a file
of at most 4 MiB (`MAX_JOBS`, `MAX_EDGE` and `MAX_FILE_BYTES` in the core;
`STATUS` names the header's statuses and a test reads them back from
`chat_lottie.h`). **A trap loses all loaded animations; the Dart side
reloads.** wasm32 cannot unwind, so a Rust panic is a
`WebAssembly.RuntimeError`, not the `-6` status that `catch_unwind` gives the
native build. The core then drops that instance, builds a fresh one from the
module it already compiled, answers the request that hit the trap with `-6`
(every job of a batch gets it), and every id issued before the trap fails with
`-1` afterwards: the caller loads again what it still needs. Ids keep
counting across the restart.

**Cross-build golden.** `native/tests/fixtures/golden_64x64_frame_30.rgba`
(16 384 bytes, premultiplied `[R, G, B, A]`, frame 30 of the repository's own
hand-authored fixture, so it is redistributable) is the one reference all
builds are held to: `native/tests/golden.rs` compares the host build and
`web/test/golden.test.mjs` both wasm builds (SIMD and plain), each within one
colour level per channel. After a deliberate change of the renderer,
regenerate it from the host build (from `native/`) and review the diff:

```sh
CHAT_LOTTIE_UPDATE_GOLDEN=1 cargo test --test golden
```

Tests run in Node only (v22; no browser):

```sh
node --test web/test
```

They build the wasm through the tool and skip with a message when `cargo`,
the wasm Rust target or `dart` is missing. `web/test/layout.test.mjs` derives
the byte offsets of `ChatLottieInfo` and `ChatLottieJob` on wasm32 from the
header and compares them with the constants in the core, so a change to
either struct fails there before it corrupts memory. Changing a crate source
file changes the manifest's `sourceHash` (`dart native/tool/source_hash.dart
--write`).

## Platforms

`package:lottie_native/lottie_native.dart` compiles on the web: the value
types are exported everywhere, and everything that needs `dart:ffi` is
exported only where the VM is (a conditional export: `native_exports_vm.dart`
is the default, and `dart.library.js_interop` swaps in the empty
`native_exports_js.dart`; the analyzer reads only the default, so the VM half
must be it). The test
`web_compile_test.dart` runs `dart compile js` on a small entry to hold this.
`package:lottie_native/testing.dart` is native-only: the fakes and contracts
use `dart:ffi`.

| Type | VM | Web |
| --- | --- | --- |
| `LottieHandle`, `LottieInfo`, `LottieFeatures`, `LottieLoadResult` (`LottieLoaded`, `LottieRejected`), `LottieRejection`, `LottieRenderStatus`, `LottieAvailability`, `LottieNativeVersion` | yes | yes |
| `LottieBinding`, `LottieRenderJob` (carries a `Pointer<Uint8>`) | yes | no |
| `LottieFrameCodec`, `LottieFrameRegion` | yes | no |
| `NativeLottieBinding`, `NativeLottieFrameCodec` | yes | no |

## Types

| Type | Role |
| --- | --- |
| `LottieBinding` | The interface: `availability` (`LottieAvailability`: `available`, `missingLibrary`, `abiMismatch`) and `isAvailable`, `load`, `renderBatch`, `dispose`, `close` (frees every live handle; later `load` / `renderBatch` throw `StateError`). A native binding, a fake and a web binding satisfy it. |
| `LottieLoadResult` | Sealed: `LottieLoaded(handle, info)` or `LottieRejected(reason)`. A bad file is a value, never an exception. |
| `LottieRejection` | `tooLarge`, `malformed`, `limitExceeded`, `unsupported`, `internal`, mirroring the wrapper's load statuses. `internal` is a bug in the wrapper, never the file's fault: do not cache it as a verdict on the file. |
| `LottieInfo` | Size, frame count, frame rate and `LottieFeatures` of a loaded file. |
| `LottieFeatures` | Bitmask of what the file uses and the renderer does not draw: effects, expressions, image layers, text layers. Informational. |
| `NativeLottieBinding` | The binding over the compiled library. `NativeLottieBinding.probe()` calls `chat_lottie_abi_version()` once; a missing library or symbol is `missingLibrary`, a version other than 1 is `abiMismatch`; any other error propagates. It logs nothing. |
| `LottieFrameCodec` / `LottieFrameRegion` | The frame cache's lz4 codec over a region of page memory (`target`, `width`, `height`, `strideBytes`): `compress` answers the packed bytes or null for a rejected region, `decompress` answers false for corrupt, wrong-size or rejected input and then touches no byte of the region. It never throws for data; unavailable, it throws `StateError`. The packed form is one lz4 block of the tight pixels, so it does not depend on the stride. The codec is in the wrapper so the web build shares it ([ADR 042](../../docs/adr/042-native-media-decoding.md)). |
| `NativeLottieFrameCodec` | The codec over the compiled library. `NativeLottieFrameCodec.probe()` follows the binding's rule and also needs its own symbol: a missing symbol or an ABI other than 1 is not available. |
| `LottieNativeVersion` | `engine`: the crate version and the pinned tlottie revision as one token, which a frame-cache key carries so a new build never replays frames an older one drew. Bump it with `native/Cargo.toml`; a test fails when it does not match the manifest. |
| `LottieRenderJob` / `LottieRenderStatus` | One frame into a slot of page memory (premultiplied RGBA, rows `strideBytes` apart); `ok`, `badArgument`, `badSize`, `failed`. A slot edge is at most `LottieRenderJob.maxEdge` (512): a decoder's size classes must not exceed it. |

## Host contract

| The host provides | The host must not |
| --- | --- |
| A binding it registers only when `isAvailable` is true: probe first (`NativeLottieBinding.probe()`), log once through its own diagnostics if the probe says no, register only on yes | Call `load` or `renderBatch` on one that is not (they throw `StateError`) |
| Page memory it owns, with the slot's top-left pixel as `target` and the page's row distance as `strideBytes` | Expect a render to touch a byte outside the slot's `width * 4` bytes of each of its rows |
| `dispose` for every `LottieLoaded` handle it is done with | Render a disposed handle (it answers `badArgument`) or share a binding across isolates |

## Testing

`package:lottie_native/testing.dart` (opt-in) exports `FakeLottieBinding`
(scripted files, a frame-derived colour per job, `available:`) and
`NativeBindingContract.run` over a `NativeBindingHarness`; likewise
`FakeLottieFrameCodec` (a header and the raw pixels; `compressFails`,
`decompressFails`) and `LottieFrameCodecContract.run` over a
`LottieFrameCodecHarness`. An implementation
runs the contract against itself:

```dart
NativeBindingContract.run(() => NativeBindingHarness(
      binding: binding,
      validBytes: validBytes,
      expectedInfo: expectedInfo,
      malformedBytes: malformedBytes,
    ));
```

## Fuzzing and benchmarks

The C ABI is fuzzed two ways. The fixed corpus replay (`native/tests/replay.rs`)
runs with `cargo test` on every pull request: prefix truncations and byte
mutations of the hand-authored fixture, the same as TGS (valid, truncated at
several points, with a damaged gzip header or trailer, a gzip bomb exactly at
the 8 MiB inflated cap and one byte over), all under the one-minute budget of
ADR 030, which the test measures over the whole replay and fails above. The
"269 zero bytes" input is a **stand-in**: ADR 030 names a known 269-byte
malformed file, but that file is not available to this repository, so the
corpus holds 269 zero bytes, which exercises the same short-input paths and
says nothing about the original. The long run is
`native/tests/fuzz_long.rs`, `#[ignore]`d so a plain `cargo test` never waits
for it; the manually dispatched workflow `.github/workflows/lottie_native_fuzz.yml` runs it
for 20 minutes with a random seed and opens or updates one issue on a finding.
It is seeded and structure-aware, not coverage-guided: a small PRNG of its own
(no crate) edits the hand-authored fixtures at the byte level (flips,
truncations, insertions, copies, deletions) and through `serde_json` (corrupt
numbers and types, renamed, dropped and inserted keys, duplicated and deeply
nested arrays, a precomp that includes itself), wraps cases in gzip and
corrupts the header, the trailer and the member structure, and now and then
sends a size bomb. Each input goes through `chat_lottie_load`, then (when it
loads) `chat_lottie_render_batch` at several sizes with hostile frame numbers
and bad jobs in the same batch, `compress_region` / `decompress_region` round
trips with a corrupt stream, a short destination and a wrong-size region, and
`chat_lottie_free`; the input is also fed to `decompress_region` as a stream.

Per input it asserts a documented status for each call, never `-6` (a caught
panic is a bug), a null handle after a failed load, premultiplied pixels, no
write outside the slot and a rejected stream leaving the region alone. Each case runs on a worker thread with a
deadline; a hang is a finding too. The harness itself is tested with planted
defects (a fake driver answering `-6`, hanging or panicking) in the same file.

```shell
cd packages/lottie_native/native
cargo test --release --test fuzz_long -- --ignored --nocapture
```

| Variable | Default | Meaning |
| --- | --- | --- |
| `CHAT_LOTTIE_FUZZ_SECONDS` | `20` | How long to generate cases. |
| `CHAT_LOTTIE_FUZZ_SEED` | the clock | Printed first; the same seed makes the same cases. |
| `CHAT_LOTTIE_FUZZ_DIR` | `target/fuzz-failures` | Where a failing input (`.bin`) and its recipe (`.txt`) are written; an `inflight-*.bin` is the case a crash that never reported was running. |
| `CHAT_LOTTIE_FUZZ_CASE_MS` | `5000` | The per-input time limit. |

The playback benchmark lives with the adapter: see "Fuzzing and benchmarks" in
`lottie_decoder`.
