# Changelog

All notable changes to `video_native` are documented in this file. The format
is loosely based on [Keep a Changelog](https://keepachangelog.com/); this
package is pre-1.0.

## [Unreleased]

### Added (Android)

- Android arm64-v8a: `TARGET=android-arm64 native/recipe/build.sh` cross-compiles
  libvpx and the four FFmpeg libraries with the NDK (API 24 unless
  `ANDROID_API` says otherwise, 16 KiB page alignment, unversioned sonames),
  and `... verify` checks the ELF files. The build hook compiles the wrapper
  with the NDK clang and bundles `libchat_video.so` plus the four libraries.
  Android x86_64 and armv7 bundle nothing and warn, as before; a missing NDK
  or prefix warns and bundles nothing instead of failing the build. Existing
  macOS builds are unchanged, except that the hook now watches
  `include/libavcodec/avcodec.h` for a missing prefix.

### Added

- The `chat_video` C wrapper over FFmpeg and libvpx, the build hook that
  compiles it and bundles the FFmpeg libraries (macOS arm64 only), and the
  Dart side: `VideoBinding`, `NativeVideoBinding`, `FakeVideoBinding` and
  `VideoBindingContract` (`testing.dart`). A host that registers a binding
  checks `isAvailable` first: with no FFmpeg build the library is simply not
  bundled.

### Changed

- The FFmpeg recipe links with `-headerpad_max_install_names`. A library built
  without it cannot be bundled by the Flutter tool, which rewrites install
  names; rebuild the prefix once with `native/recipe/build.sh`.
