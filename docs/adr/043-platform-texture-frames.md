# ADR 043: Platform texture frames for playing media

A playing vector animation or video can be shown through a **platform
texture** that a render worker writes into, instead of a slot on a dynamic
page that becomes a new `ui.Image` on the UI isolate every time it changes.
It is a third paint capability of `AssetPaintable`, next to `paint` and the
sprite. Where a platform has no texture host, or the host has no texture to
spare, the dynamic pages of [ADR 022](022-asset-cache-and-media-pipeline.md)
carry the frames as before.

**Status**: Accepted  
**Date**: 2026-11-08  
**Amended**: 2026-11-09 (native-media ticket 87): a held texture keeps its last frame (row *Kept leases*); 2026-11-09 (native-media ticket 108): a warm makes room from idle textures of other classes, and a lease still on a slot asks for a texture at every sweep (row *Pool*)  
**Amended**: 2026-11-09 (native-media ticket 110): each lease waits only for its own frame in flight (row *Pacing*, section *Amendment: each lease waits only for its own frame*)
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
| Paint capability | `AssetPaintable` gains an optional **texture** next to `sprite`: a texture id, its pixel size and the size of the frame centred in it, or null. A paintable exposes it only after it was advanced (`advancePlayback`) and only once a first frame was posted to it; until then it exposes its sprite or paints its still, as now. A surface that can composite (a render object that pushes layers: the catalogue viewport, `ContentView`, the chat's emoji-only body) advances the paintable, then adds a texture layer where `AssetFit.placeTexture` puts the frame and does not call `paint` for that asset; a surface that only has a canvas ignores the capability and calls `paint`, which keeps drawing through the pages. No consumer is required to support textures. |
| Who decides | The paintable decides per lease: it takes a texture when a texture host is registered with the scope, the asset is playing and a texture of its size class is free; otherwise it takes a page slot. A lease never blocks on a texture and never fails because none is free. |
| Texture host seam | `catalog_assets` defines the seam and depends on no platform code: create and destroy a texture, `lock` (a pointer and a row stride) and `post` by texture id, and the host's fixed pixel format (premultiplied RGBA or BGRA, one per host). The lock and post calls run on the render isolates, so the host also gives the addresses of its C `lock` and `post` functions, which a render isolate calls through FFI; a decoder never imports the plugin. A host is registered with the asset scope at start-up. The fake in `testing.dart` backs targets with plain memory and records calls; a contract suite holds every host to the seam. |
| Pool | Textures are square, at the edge of a size class of the dynamic pages (64, 128, 256, 384, 512 px), and pooled by class. A lease never creates a texture: it takes an idle one or answers none, and the asset keeps its page slot. The host warms a number per class when a surface that plays opens (`warm`), off the frame path; warming waits while a surface scrolls, so a texture is never created during a glide. A released texture idles in the pool; past an idle limit the oldest is destroyed, and memory pressure destroys every idle one. The pool has its own byte budget (default 48 MiB, every buffer of the platform's queue counted), apart from each decoder's page budget. A warm the budget does not cover destroys idle textures of other classes, released longest ago first, to make room (never a leased one); textures warmed for a surface that is gone would otherwise hold the budget while the surface on screen plays from pages. A lease on a slot that may take a texture asks its class to be warmed when it begins and again at every sweep, so a lease that left a canvas, or began while the budget was spent, does not stay on a slot for its whole life. |
| Writing | The render worker writes the frame straight into the locked target at its stride, then posts: no page memory, no copy on the UI isolate. An asset that is not square is written at its fitted size with transparent margins, as on a page slot. The Lottie wrapper and the video wrapper already render into a caller buffer with a stride, so the engines do not change; the frame cache restores into the locked target the same way, reading a persisted frame from its file on the render isolate ([ADR 022](022-asset-cache-and-media-pipeline.md), *Amendment: frames read from the file*). A target that cannot be locked at once is skipped for that frame (the texture keeps its previous frame); the worker never waits for the compositor. |
| Pacing | The scheduler that asks frames for slots asks them for textures: the same fps cap by size, the same pause layers and the same idle release. A texture is posted at most once per frame of the clock. Each lease waits only for its own frame in flight, and each texture frame is a write of its own (*Amendment: each lease waits only for its own frame*). |
| Compositing | A consumer adds texture layers inside its own clip and in paint order: anything it paints under a cell (a press wash) stays in the picture before the layer, anything over a cell goes in a picture after it. A texture layer cannot crop and always shows its whole square, so the frame, not the square, is fitted: a cover fit (a GIF cell) gets a clip layer of its own, as does a corner radius; an opacity below one wraps the texture layer in an opacity layer. Stills and glyphs stay in the batched atlas draw; only playing assets become layers. |
| Platforms | Android: a texture is a `SurfaceProducer` and its window (`ANativeWindow_lock` / `unlockAndPost`). iOS and macOS: a `FlutterTexture` over a small ring of IOSurface-backed `CVPixelBuffer`s (a `CVPixelBufferPool` with at most three out: the newest, the engine's previous frame, the one being written), premultiplied BGRA; the post signals `textureFrameAvailable` on the main thread. Windows and Linux: no texture host in the first build (pages with the synchronous upload where the engine has it). Web: no texture host; the worker path of ADR 042 stays. |
| Package | One new plugin package, `frame_texture`: the Android and Apple hosts, their C entry points for the worker (`lock` / `post` by texture id), and the Dart implementation of the seam. It depends on `catalog_assets` for the seam only; the decoders do not depend on it, they see the seam. |
| Consumers | The catalogue viewport (sticker grids), `ContentView` (the GIF grid, the pack strip, composer emoji) and the chat's emoji-only body (sticker and GIF messages, custom emoji drawn large). Both of the last two composite through one path in `catalog_assets`; an inline embed reaches it as a `CompositingEmbed`, which the emoji-only body composites while one of its embeds plays. The markdown body's inline emoji stay on the canvas: the engine that lays the text out hands the embed a canvas only. A surface signals that it composites by advancing the paintable before it paints; a `paint` with no advance at the same clock time is a surface that only has a canvas, which keeps the asset on pages. |
| Kept leases | A surface that holds its playback (`AssetBinding.held`, [ADR 022](022-asset-cache-and-media-pipeline.md)) still composites the texture it last showed, and paints nothing new. A paint is the sweep's only sign of a lease on screen, so the paintable keeps its lease while kept (`AssetPaintable.keepFrame`): the sweep passes it, it does not move from its slot to a texture, and it renders nothing until a paint asks for a new frame. Let go, it counts as painted then and lives one more idle period. Without it the texture would idle, be leased by another asset after the reuse delay and show that asset's frames under the held surface's layer. |
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
- iOS and macOS: the cost of a texture layer per asset under Metal. Not
  measured. (Resolved: `textureFrameAvailable` may not be called from the
  worker's thread. On both platforms it ends in
  `Shell::OnPlatformViewMarkTextureFrameAvailable`, which checks that it runs on
  the platform task runner, the main thread; the Apple host's post dispatches
  the signal to the main queue, coalesced per texture.)
- Whether the glass blur behind floating chrome samples texture layers the way
  it samples pictures. Not checked.
- The raster cost of many texture layers in a chat with dozens of playing
  stickers. The prototype measured a grid of about 20.

## Related

- The measurements above come from the scroll lab's tape replays
  (`example/tool/scroll_lab/`), judged by visible hitches per second of motion.
- Glossary: [Content and assets](../content/CONTEXT.md).

## Amendment: leases of a kept panel

Native-media ticket 100. A hidden panel and an off-screen page hold their
catalogue's bindings ([ADR 025](025-panel-shell-and-pages.md) *the pager
keeps its pages*), so their leases are kept through the sweep where they are,
on a slot or a texture, and show their frame at once when the panel shows
again. A cell that leaves the attach window gives its lease back as before;
its entry and its position stay in the cache. Kept leases count against the
texture and page budgets like painted ones: a kept panel can leave fewer
textures for the chat, which then plays on page slots.

## Amendment: each lease waits only for its own frame

Native-media ticket 110. The schedulers kept one batch in flight for every
lease: while it ran, every next tick was skipped for all of them, so one
slow frame (a panel of stickers rendering, a slow video worker) cost every
other animation that clock frame, and a batch is answered whole, so each
texture in it was posted only when the slowest job ended. With the sticker
panel open, a chat sticker measured about 40 changes a second at an uneven
cadence instead of 60.

| Area | Decision |
| ---- | -------- |
| In flight | Per lease. A lease with a frame being rendered or written is sent nothing more until it ends, and its latest want goes out on the first tick after; no lease waits for another's frame. |
| Granularity | The leases on page slots of one tick share one atlas batch (a page is uploaded once for the cells that changed on it); each lease on a texture is a write of its own, so its post lands when its own frame is done. |
| Overlap | Batches and writes of different ticks overlap. The atlas runs its batches one after the other; the Lottie render isolate answers requests in arrival order, and a video clip's writes go to the worker that decodes it; a lease has at most one frame out, so its frames land in order. |
| Kept rules | A texture is posted at most once a clock frame (one frame out per lease, sent only on a tick); a texture is shown after three posts of its lease (ticket 82); a texture a lease lets go during its write goes back to the pool when that write ends; a lease with a frame in flight moves to a texture only after it ends, so a write always names the texture its lease holds. Kept leases, the parity fills and the frame-file reads are unchanged. |
| Cost | One isolate message per texture frame instead of one per tick; the posts of a tick no longer land together, which ticket 99 (posts of a tick in one burst) has to weigh against per-lease cadence. |
| Not changed | One Lottie render isolate ([ADR 042](042-native-media-decoding.md), *Workers*): leases still share its time. A slow frame now delays only the frames queued behind it on that isolate, not a whole tick of every lease. |
