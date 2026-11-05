# Changelog

All notable changes to `lottie_native` are documented in this file. The format
is loosely based on [Keep a Changelog](https://keepachangelog.com/); this
package is pre-1.0.

## [Unreleased]

### Added

- `LottieBinding`, the interface to the native Lottie renderer, with its load
  result, info, features bitmask and render job types.
- `testing.dart`: `FakeLottieBinding` and `NativeBindingContract`, which every
  binding runs against itself, including a check that a render stays inside
  its slot.
- `NativeLottieBinding` over hand-written `@Native` bindings of
  `chat_lottie.h`, with a one-time `probe()`, and `hook/build.dart`, which
  compiles the `native/` crate with cargo on macOS (arm64, x86_64). Other
  targets fail with an `UnsupportedError` until prebuilt libraries land.

### Changed

- Every wrapper status has its own number (`-6` internal, `-7` bad size, `-8`
  render failed); `LottieRejection.internal` and `LottieAvailability`
  (`missingLibrary`, `abiMismatch`) replace the hidden probe reason.
- `LottieBinding.close()` frees every live handle; `LottieRenderJob.maxEdge`
  is the slot edge cap.
- An unsupported build target emits no asset and logs a warning instead of
  failing the build.
