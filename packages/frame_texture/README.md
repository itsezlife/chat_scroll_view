# frame_texture

The platform texture hosts of [ADR 043](../../docs/adr/043-platform-texture-frames.md):
textures a render worker writes a playing asset's frames into, which a surface
composites as texture layers. It implements the `FrameTextureHost` seam of
`catalog_assets`; decoders never import it, they see the seam and its C entry
points.

## Use

```dart
final host = createPlatformFrameTextureHost(); // null where there is none
final pool = host == null ? null : FrameTexturePool(host: host);
// AssetCacheScope(textures: pool, ...); dispose the pool after the scope.
```

## Platforms

| Platform | Texture | Verified |
| --- | --- | --- |
| Android | a `SurfaceProducer`; its window locked with `ANativeWindow_lock` and posted with `unlockAndPost`, premultiplied RGBA | the table on the host (fake window); the device smoke check is pending |
| iOS, macOS | none yet (a later ticket: `FlutterTexture` over `CVPixelBuffer`s) | |
| Windows, Linux, web | none | |

## Layout

| Path | Role |
| --- | --- |
| `native/include/frame_texture.h` | The C ABI: `frame_texture_lock`, `frame_texture_post` (the worker's), the plugin's attach / detach / forget |
| `native/src/frame_texture.c` | The texture table: windows by id, the lock state of each |
| `native/src/frame_texture_jni.c` | The JNI side the Kotlin plugin calls |
| `native/test/fake_window.c` | A fake `ANativeWindow`, so the tests run the real table on the host |
| `android/` | The Kotlin plugin and the CMake build of `libframe_texture.so` |
| `lib/` | `PlatformFrameTextureHost` (channel + FFI) and the factory |

## The C ABI

```c
void* frame_texture_lock(int64_t texture_id, int32_t* row_stride);
void  frame_texture_post(int64_t texture_id);
```

`lock` answers NULL at once for a texture that is unknown, destroyed, without
a surface now, or locked or being posted by another caller; it never waits on
another caller. Every function may be called from any thread.
`FrameTextureHost.entryPoints` gives their addresses to a render isolate.

## How the library loads

The Android Gradle Plugin builds `libframe_texture.so` from
`android/CMakeLists.txt` with the app's NDK (16 KB page aligned), so it ships
in the plugin's own module, next to the Kotlin that needs it. The plugin loads
it with `System.loadLibrary`; the Dart side opens `libframe_texture.so` by
name, which the dynamic linker answers with the instance already loaded in the
app's namespace: one table in the process.

## Tests

`flutter test test/unit_test.dart` compiles the table with the fake window
with the host's `cc` (skipped where there is none) and runs the
`FrameTextureHostContract` of `catalog_assets` over it, with the plugin's side
played over a mock channel. The smoke check on a device is
`example/integration_test/frame_texture_smoke_test.dart`.
