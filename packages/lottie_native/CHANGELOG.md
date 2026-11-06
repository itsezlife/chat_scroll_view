# Changelog

All notable changes to `lottie_native` are documented in this file. The format
is loosely based on [Keep a Changelog](https://keepachangelog.com/); this
package is pre-1.0.

## [Unreleased]

### Changed

- `package:lottie_native/lottie_native.dart` now compiles for the web. The
  value types (`LottieHandle`, `LottieInfo`, `LottieFeatures`,
  `LottieLoadResult`, `LottieRejection`, `LottieRenderStatus`,
  `LottieAvailability`, `LottieNativeVersion`) are exported everywhere; the
  `dart:ffi` types (`LottieBinding`, `LottieRenderJob`, `LottieFrameCodec`,
  `LottieFrameRegion`, `NativeLottieBinding`, `NativeLottieFrameCodec`) only
  through a conditional export that is empty on the web. Nothing changes on
  the VM: the same names from the same barrel. `LottieHandle`,
  `LottieAvailability` and `LottieRenderStatus` moved out of
  `src/lottie_binding.dart` into files of their own; code importing that
  `src/` path for them must import the barrel.

### Added

- Web build: the crate exports `chat_lottie_alloc` / `chat_lottie_dealloc` on
  wasm32 (a region of 1 byte to 256 MiB; anything else returns null), and
  `web/` holds `chat_lottie_core.mjs` (load, one-call batch render into pooled
  scratch regions, dispose; SIMD chosen by a `WebAssembly.validate` probe) and
  `chat_lottie_worker.js` (a module worker with a documented message protocol;
  pixel buffers are transferred). `dart native/tool/build_web.dart --out <dir>`
  writes the SIMD and no-SIMD wasm files next to them; the output is not
  committed. Tested in Node with `node --test web/test`; see the README, "Web
  build".


- A seeded long fuzz of the C ABI (`native/tests/fuzz_long.rs`, ignored by
  default) and a nightly workflow that opens an issue on a finding.
- `LottieNativeVersion.engine`: the crate version and pinned tlottie revision
  as one token, part of every frame-cache key; a test compares it with
  `native/Cargo.toml`.
- `native/tool/assemble_manifest.dart` builds `prebuilts.json` from a directory
  of built libraries (header, duplicate and `--require` checks, re-read
  verification); `source_hash.dart --check` fails on a stale recorded hash;
  two GitHub workflows (untested on GitHub) publish the prebuilts and gate
  crate changes. See the README, "Publishing prebuilts".
- `LottieBinding`, the interface to the native Lottie renderer, with its load
  result, info, features bitmask and render job types.
- `testing.dart`: `FakeLottieBinding` and `NativeBindingContract`, which every
  binding runs against itself, including a check that a render stays inside
  its slot.
- `NativeLottieBinding` over hand-written `@Native` bindings of
  `chat_lottie.h`, with a one-time `probe()`, and `hook/build.dart`, which
  compiles the `native/` crate with cargo.

- `LottieFrameCodec` and `NativeLottieFrameCodec`: the frame cache's lz4
  compress / decompress of a region of page memory, over three new C
  functions (`chat_lottie_lz4_bound`, `chat_lottie_compress_region`,
  `chat_lottie_decompress_region`) built on `lz4_flex` (pure Rust, no unsafe).
  A failed decompress writes nothing. `testing.dart` adds
  `FakeLottieFrameCodec` and `LottieFrameCodecContract`.

- `hook/build.dart` delivers the native library in order: compile from source
  when `build_from_source` (pubspec user-define) or
  `LOTTIE_NATIVE_BUILD_FROM_SOURCE=1` is set; else download the hash-pinned
  prebuilt listed in `native/prebuilts.json` (size and SHA-256 verified,
  cached in the hook's shared directory, never fatal); else compile if the
  host can and cargo exists; else bundle nothing and warn. No prebuilt is
  published yet and the manifest is empty, so builds still compile.
  `native/tool/source_hash.dart [--write]` and
  `native/tool/manifest_entry.dart` maintain the manifest. Adds `crypto`.

- `hook/build.dart` builds from source for iOS (device, simulator arm64 and
  x64), Android (arm64-v8a, x86_64) and, on a matching host, Linux and
  Windows, not only macOS. Android finds the NDK (`ANDROID_NDK_HOME`,
  `ANDROID_NDK_ROOT`, the highest under the SDK's `ndk/`), links with its
  clang wrapper for the app's API level and always passes
  `max-page-size=16384`; the built library's ELF alignment and machine, or
  Mach-O CPU, are checked before it is bundled. A host that cannot build a
  target, or an Android build without an NDK, bundles nothing and warns,
  naming the prebuilt route. Opt-in cross-compile smoke:
  `LOTTIE_NATIVE_CROSS=1`.

### Changed

- The hook declares every crate source file as a dependency instead of the
  `native/src/` directory: editing an existing file there did not re-run the
  hook, so stale native code could ship. A host without cargo (and with no
  prebuilt) now gets no asset and a warning instead of a failed build.

- Every wrapper status has its own number (`-6` internal, `-7` bad size, `-8`
  render failed); `LottieRejection.internal` and `LottieAvailability`
  (`missingLibrary`, `abiMismatch`) replace the hidden probe reason.
- `LottieBinding.close()` frees every live handle; `LottieRenderJob.maxEdge`
  is the slot edge cap.
- An unsupported build target emits no asset and logs a warning instead of
  failing the build.
