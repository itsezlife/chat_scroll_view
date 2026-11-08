# ADR 043: Platform texture frames for playing media

A playing vector animation or video can be shown through a **platform
texture** that a render worker writes into, instead of a slot on a dynamic
page that becomes a new `ui.Image` on the UI isolate every time it changes.
It is a third paint capability of `AssetPaintable`, next to `paint` and the
sprite. Where a platform has no texture host, or the host has no texture to
spare, the dynamic pages of [ADR 022](022-asset-cache-and-media-pipeline.md)
carry the frames as before.

**Status**: Proposed  
**Date**: 2026-11-08  
**Relates to**: [ADR 022](022-asset-cache-and-media-pipeline.md) (paint surface, dynamic frame pages), [ADR 042](042-native-media-decoding.md) (engines, workers), [ADR 020](020-package-topology.md), [ADR 024](024-panel-catalog-seams.md), [ADR 030](030-testing-policy.md)

## Context

Every frame of a playing asset reaches the screen as a new image made from page
bytes. `dart:ui` has no way to change an existing image or a part of one, so
each change is a whole-image upload started on the UI isolate. On a 120 Hz
phone, replaying the maintainer's recorded scroll of a sticker grid (profile
build, interleaved arms):

- The UI isolate spent 2.9 to 3.3 s of a 28 s replay inside upload calls,
  about 0.4 ms an upload. A 256 KiB copy costs tens of microseconds, so the
  cost is the engine's work per image, not the bytes.
- `decodeImageFromPixelsSync` cut that to about 1 s and the visible hitches by
  about 40%; it is now the upload path where the engine has it. The work moves
  to the raster thread.
- Flutter GPU (`Texture.overwrite` into one texture per page, one image over
  it) made each upload three times dearer.
- A prototype that drew the grid's animated cells as platform textures, with
  the render worker writing each frame straight into the texture's buffer,
  cut the UI time in uploads by 84% and the hitches while gliding by about 60%
  against the asynchronous upload. Its costs: a compositing layer per cell
  (raster p50 +0.3 to 0.5 ms), 40 ms to a cell's first frame (p50; the still
  shows meanwhile), and hitches when textures were created during a glide.

The reference client on Android renders each sticker into its own bitmap on a
background thread and swaps references; the system's render thread uploads
it. Its main thread never builds an image per frame. A platform texture is the
Flutter shape of that: the engine reads the newest buffer on the raster
thread, and the UI isolate only places a layer.

## Decided

| Area | Decision |
| ---- | -------- |
| Paint capability | `AssetPaintable` gains an optional **texture** next to `sprite`: a texture id and its pixel size, or null. A paintable exposes it only after it was advanced (`advancePlayback`) and only once a first frame was posted to it; until then it exposes its sprite or paints its still, as now. A surface that can composite (a render object that pushes layers) adds a texture layer at the fitted rectangle and does not call `paint` for that asset; a surface that only has a canvas ignores the capability and calls `paint`, which keeps drawing through the pages. No consumer is required to support textures. |
| Who decides | The paintable decides per lease: it takes a texture when a texture host is registered with the scope, the asset is playing and a texture of its size class is free; otherwise it takes a page slot. A lease never blocks on a texture and never fails because none is free. |
| Texture host seam | `catalog_assets` defines the seam and depends on no platform code: lease a texture of a size class, release it, and a write target per texture (`lock` gives a pointer, a row stride and the pixel format; `post` publishes what was written). A host registers one implementation with the scope at start-up. The fake in `testing.dart` records leases and posts and backs targets with plain memory. |
| Pool | Textures are pooled by size class (the classes of the dynamic pages, at most 512 px). The host warms a configurable number per class when a surface that plays opens, off the frame path; a texture is never created while a surface scrolls. A released texture idles in the pool and is destroyed on memory pressure or past a host-configured count. Textures count against the dynamic budget in bytes (every buffer of the platform's queue). |
| Writing | The render worker writes the frame straight into the locked target at its stride, then posts: no page memory, no copy on the UI isolate. The Lottie wrapper and the video wrapper already render into a caller buffer with a stride, so the engines do not change; the frame cache restores into the locked target the same way. A target that cannot be locked at once is skipped for that frame (the texture keeps its previous frame); the worker never waits for the compositor. Pixels stay premultiplied; the host states the channel order it locks with. |
| Pacing | The scheduler that asks frames for slots asks them for textures: the same fps cap by size, the same pause layers and the same idle release. A texture is posted at most once per frame of the clock. |
| Compositing | A consumer adds texture layers inside its own clip and in paint order: what paints over a cell (a press highlight, a selection mark) goes in a picture after the texture layer. An opacity below one wraps the texture layer in an opacity layer. Stills and glyphs stay in the batched atlas draw; only playing assets become layers. |
| Platforms | Android: a texture is a `SurfaceProducer` and its window (`ANativeWindow_lock` / `unlockAndPost`). iOS and macOS: a `FlutterTexture` over a small ring of IOSurface-backed `CVPixelBuffer`s. Windows and Linux: no texture host in the first build (pages with the synchronous upload where the engine has it). Web: no texture host; the worker path of ADR 042 stays. |
| Package | One new plugin package, `frame_texture`: the Android and Apple hosts, their C entry points for the worker (`lock` / `post` by texture id), and the Dart implementation of the seam. It depends on `catalog_assets` for the seam only; the decoders do not depend on it, they see the seam. |
| Consumers | First the catalogue viewport (sticker and GIF grids, the pack strip), then the chat's sticker and GIF bodies. |
| Failure | A host that cannot create a texture, or a lock that fails repeatedly, sends that asset back to a page slot: never a visible failed stage, per ADR 022. |

## Why

- The measured gain is the cost the UI isolate stops paying per frame, and it
  grows with the number of playing assets, which is what a sticker grid and a
  busy chat have most of.
- Keeping pages as the fallback keeps every platform working and lets each
  host land on its own: web, desktop and a device whose producer refuses CPU
  writes lose nothing they have today.
- A seam with lock and post leaves the engines and the frame cache as they
  are: they already write into a caller buffer with a stride.
- A pool warmed off the frame path removes the one hitch source the prototype
  showed (creating textures during a glide).

## Rejected

| Alternative | Why not |
| ----------- | ------- |
| Uploads through Flutter GPU (`Texture.overwrite`) | Measured three times dearer per upload than the asynchronous upload; experimental API, Impeller only |
| `decodeImageFromPixelsSync` as the end state | Kept as the page upload, but it still makes an image per change and moves the work to the raster thread; the texture path removes it |
| A texture per page instead of per asset | A page change would still rewrite the whole page, and four unrelated assets would share one buffer queue |
| The worker registering windows through its own JNI export (the prototype) | Ties a decoder's native library to the host activity; the plugin owns platform objects, the worker only locks and posts |
| An engine patch for in-place image updates | Not ours to ship; it can replace the texture path later without changing the seam |

## Open and unverified

- Whether every Android producer accepts CPU writes into its window; verified
  on one device (Samsung SM-S938B, Impeller, Vulkan). The failure rule covers a
  refusal, but how often it happens is unknown.
- iOS and macOS: whether `textureFrameAvailable` may be called from the worker's
  thread, and the cost of a texture layer per asset under Metal. Not measured.
- Whether the glass blur behind floating chrome samples texture layers the way
  it samples pictures. Not checked.
- The raster cost of many texture layers in a chat with dozens of playing
  stickers. The prototype measured a grid of about 20.

## Related

- The measurements above come from the scroll lab's tape replays
  (`example/tool/scroll_lab/`), judged by visible hitches per second of motion.
- Glossary: [Content and assets](../content/CONTEXT.md).
