# Changelog

All notable changes to `frame_texture` are documented in this file. The format
is loosely based on [Keep a Changelog](https://keepachangelog.com/); this
package is pre-1.0.

## [Unreleased]

### Added

- The Android texture host (ADR 043): a `SurfaceProducer` per texture, its
  window kept by texture id in `libframe_texture.so`, which exports
  `frame_texture_lock` / `frame_texture_post` for the render workers.
- `PlatformFrameTextureHost`, the `FrameTextureHost` of `catalog_assets` over
  the plugin's channel and the C table, and `createPlatformFrameTextureHost`.
- The iOS and macOS texture host (one `darwin/` source): a `FlutterTexture`
  per texture over a pool of at most three IOSurface-backed BGRA
  `CVPixelBuffer`s, the same `frame_texture_lock` / `frame_texture_post` ABI,
  `textureFrameAvailable` sent on the main thread, and spare buffers freed on
  memory pressure. `createPlatformFrameTextureHost` answers a BGRA host there.
