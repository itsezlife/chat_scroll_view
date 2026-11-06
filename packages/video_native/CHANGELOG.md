# Changelog

All notable changes to `video_native` are documented in this file. The format
is loosely based on [Keep a Changelog](https://keepachangelog.com/); this
package is pre-1.0.

## [Unreleased]

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
