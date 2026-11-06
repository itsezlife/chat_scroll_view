# lottie_native

The binding interface to the native Lottie renderer (tlottie behind a batch C
API, [ADR 042](../../docs/adr/042-native-media-decoding.md)): load a file,
render frames into page memory, dispose. A leaf of the workspace
([ADR 020](../../docs/adr/020-package-topology.md), rule 8): it depends on no
workspace package and is reached through its decoder only.

This package holds the interface, the fake, the contract, the native binding
(`NativeLottieBinding`) and the build hook that delivers the compiled library.

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
3. **Compile from source** when this host builds the target (macOS arm64 and
   x86_64 today) and `cargo` is found; otherwise **no asset** and a warning
   that names the target: the build succeeds and
   `NativeLottieBinding.probe()` reports `missingLibrary`.

`cargo` is found on `PATH`, then under `CARGO_HOME`, then in `~/.cargo/bin`;
without Rust and with the flag on, the build fails and says to install it from
[rustup.rs](https://rustup.rs). When cargo fails for a missing Rust target the
message ends with the `rustup target add` line. A first source build needs
network for the crates and the pinned tlottie commit.

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
  bare file name appended to it. Hex values are lower case.
- An empty `baseUrl` or `artifacts` means "no prebuilt", never an error. A
  manifest that does not parse is ignored with a warning.
- `sourceHash` is the SHA-256 over this listing: the files `Cargo.toml`,
  `Cargo.lock`, everything under `include/` and everything under `src/` (all
  in `native/`), sorted by `/`-separated relative path, each as
  `<path> LF <byte length> LF <bytes> LF`. Bytes are hashed as stored, so a
  checkout that rewrites line endings falls back to compiling.

### Publishing prebuilts (maintainer)

1. Build the library for each target from the current sources.
2. Upload the files so that `baseUrl` + `file` resolves to each.
3. For each file, print its entry and paste it under `artifacts`:
   `dart native/tool/manifest_entry.dart <file>` prints `sha256` and `size`.
4. Set `baseUrl`, then run `dart native/tool/source_hash.dart --write` from
   the package root. It records the current `sourceHash` and the crate
   version; without `--write` it only prints the hash. (Use `dart <file>`,
   not `dart run`, which would run the build hook.)

After any edit to the crate, re-run step 4 only once new libraries are
published; until then the stale `sourceHash` correctly disables the old
artifacts.

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
