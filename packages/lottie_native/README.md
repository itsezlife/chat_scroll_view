# lottie_native

The binding interface to the native Lottie renderer (tlottie behind a batch C
API, [ADR 042](../../docs/adr/042-native-media-decoding.md)): load a file,
render frames into page memory, dispose. A leaf of the workspace
([ADR 020](../../docs/adr/020-package-topology.md), rule 8): it depends on no
workspace package and is reached through its decoder only.

This package holds the interface, the fake, the contract, the native binding
(`NativeLottieBinding`) and the build hook that compiles `native/` with cargo.

## Building

`hook/build.dart` runs `cargo build --release` on the `native/` crate for the
build's macOS architecture (arm64 or x86_64) and registers the dylib as a
bundled code asset. It finds `cargo` on `PATH`, then under `CARGO_HOME`, then
in `~/.cargo/bin`; without Rust it fails and says to install it from
[rustup.rs](https://rustup.rs). Other targets emit no asset and log a warning that
the library is then unavailable at run time (the probe reports
`missingLibrary`) until slice 6 (hash-pinned prebuilt libraries and an opt-in
compile flag). When cargo fails for a missing Rust target, the message ends
with the `rustup target add` line. A
first build needs network for the crates and the pinned tlottie commit.

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
runs with `cargo test` on every pull request. The long run is
`native/tests/fuzz_long.rs`, `#[ignore]`d so a plain `cargo test` never waits
for it; the nightly workflow `.github/workflows/lottie_native_fuzz.yml` runs it
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
