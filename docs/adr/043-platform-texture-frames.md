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
**Amended**: 2026-11-09 (native-media ticket 116): a texture is given back when its lease's paintable leaves the screen (section *Amendment: textures given back on leaving*)
**Amended**: 2026-11-10 (native-media ticket 144): a texture given back on leaving keeps its frame for its asset, which takes it back and shows it at once; a video clip continues on its next lease (section *Amendment: a cell that comes back keeps its frame*)
**Amended**: 2026-11-10 (native-media ticket 148): a cell that comes back goes on from its own frame at once: a video clip keeps its decoded-ahead frames, a Lottie lease does not render its kept frame again, a playing image keeps the time its frame was up (section *Amendment: a cell that comes back goes on at once*)
**Amended**: 2026-11-10 (native-media ticket 150): a video clip goes on from where it left only with its decoded-ahead frames and its frame shown at once; otherwise it starts over; the kept-ahead budget is 24 MiB; a texture not shown yet is posted its frame again (section *Amendment: a clip that cannot go on smoothly starts over*)
**Amended**: 2026-11-10 (native-media ticket 151): the idle sweep releases no lease while the clock is paused, so a pause no longer sends every texture on screen through the kept-frame path ([ADR 022](022-asset-cache-and-media-pipeline.md), *Amendment: a paused clock keeps its leases; focus loss on a phone plays on*)
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

*Amended by ticket 201* (*Amendment: a hidden panel gives its textures
back*): a panel held on screen (moving, under a sheet) still keeps its
textures; a hidden one gives them back keeping their frames.

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
| Render isolates | With one Lottie render isolate the leases still shared its time, and the chat's sticker queued behind a panel's cells (measured worse than before, about 30 changes a second): Lottie renders on a pool of isolates, and a tick sends its largest texture frames first ([ADR 042](042-native-media-decoding.md), *Amendment: a pool of render isolates*). |

## Amendment: textures given back on leaving

Native-media ticket 116. A fling through a sticker panel ended with every texture leased (33 leased, none idle) by cells that had flown past, released only by the sweep. The rules are in [ADR 022](022-asset-cache-and-media-pipeline.md), *Amendment: a lease is given back on leaving*; what they mean for textures:

| Area | Decision |
| ---- | -------- |
| Leaving | A lease whose paintable left the screen gives its texture back once the frame is over, unless painted in it or kept, through the same path as any release: a texture a write still names goes back when that write ends, and the pool's reuse delay applies before another lease takes it. A cell hidden but still drawn in that frame (one at the edge of a scrolling window) keeps its texture, so it never falls back to its still for three posts. |
| Full pool | A full pool takes page slots from stale leases, never a texture: handing a texture straight to another lease would skip the reuse delay, while the surface that last composited it may still be drawn with it. A lease that found no texture plays from the slot it got and moves to an idle texture on a later tick, as before. |
| Kept leases | Unchanged: a kept lease is never given back on leaving, never taken, never swept. |

## Amendment: a cell that comes back keeps its frame

Native-media ticket 144. A cell that left the screen gave its texture back (ticket 116); when it came back its new lease took any idle texture and showed the first-frame still until three posts of its own, and a video clip started over. The reference client keeps a detached animation whole in a memory cache (`ImageLoader.lottieMemCache`, 10 MiB): `RLottieDrawable.removeParentView` / `addParentView` keep `currentFrame` and `renderingBitmap`, and `AnimatedFileDrawable.removeParent` / `addParent` keep its decoder where it was, so the next draw shows the last bitmap.

| Area | Decision |
| ---- | -------- |
| Kept frame | A lease that ended because its paintable left the screen, a full pool took it, or the sweep found it unpainted gives its texture back naming its key (`FrameTextureLease.release(showing:)`), once the texture is shown. The pool keeps that texture for the key: a lease of the same key (`lease(showing:)`) takes it back first, without the reuse delay (every frame queued on it is the asset's own), and is shown at once (`FrameTextureLease.showsFrame`, no three posts). A lease its holder releases (a disposal, a restart, a rewind, a pass resting on its first frame) keeps nothing, and a disposed paintable forgets what its key kept (`forget`). |
| Others | Another lease takes an idle texture that keeps no frame first, and a kept one only when none is left; that one forgets its frame and is shown after three posts as before. A warm does not count kept textures as idle, so the cells coming on screen get textures of their own. |
| Cost | Kept textures are idle textures that would otherwise be reused: at most `keptFrameBytes` (24 MiB by default, half the pool's unchanged 48 MiB budget; about a screen of panel cells on Android at 1 MiB each, 256 px with four buffers), the one kept longest forgotten first. The idle limit, memory pressure and a warm of another class making room destroy them as any idle texture. Nothing is copied or rendered to keep a frame. |
| Video | A clip whose lease ended that way continues on its next lease (`VideoFrameScheduler.acquire(after:)`): clip time, pass timeline and the decoder's position carry over, with no rewind. The frames the old lease had decoded ahead are dropped, so the clip holds its frame for those few frames' time before it moves on. *Superseded by ticket 148* (*Amendment: a cell that comes back goes on at once*): the decoded-ahead frames stay within a budget. On a page slot the frame stays too (`FrameHandle.release(keepFrame:)` overrides the video atlas's forgetting of idle frames). |
| Lottie on slots | Unchanged: an idle slot already keeps its frame, and the paintable's played time carries over. |
| Not kept | A texture not shown yet (its queue may hold another asset's frames), a failed lease, a slot a shown texture replaced. Past the kept budget a cell that comes back shows its still for three posts, as before. |

## Amendment: a cell that comes back goes on at once

Native-media ticket 148. Measured on device (screen recording at 30 fps of a video sticker's ring size in a panel recents cell, three returns after about 300 ms away): the cell came back on a frame, held it for about eight recorded frames (270 ms), then jumped several frames ahead. The reference client's `AnimatedFileDrawable` keeps its decoder and its next decoded bitmap across `removeParent` / `addParent`, so a sticker back on screen shows the frame it left on and the next one at its time.

The hold and the jump are one cause. Ticket 144 carried a returning clip's time and its decoder's position, but dropped the ring of frames the old lease had decoded ahead. Decoding is sequential and the decoder was past those frames, so the first frame the new lease decoded was three or four frames after the one on show: the clip held its kept frame until its own time reached that frame, then showed it, skipping the ones dropped. That looks like a jump to the shared clock's time; the clip's time itself stood still while it was away (the paintable's `playbackResumed`). The device-shaped test (`example/test/flicker/panel_video_return_test.dart`, frame indices stamped into the fake engine's pixels) showed it: frame 56 left, 56 back, held ten display frames, then 60.

| Area | Decision |
| ---- | -------- |
| Video | A lease that ended where its clip may go on from (leaving, a full pool, the sweep) parks its player whole: clip time, decoder position, the ring and a frame picked but not sent. The next lease of the key takes that player back (`acquire(after:)`), so the next frame shows at its time. The player decodes nothing while parked and drops its spare buffers. A frame drawn or written ends one buffer, not every frame the player is drawing, since a returning lease may send a frame while its old lease's write is still out. |
| Clip time | The returning player takes the next played time as the start of its timing, whatever the paintable reports: an absent clip's time stands still even when no `playbackResumed` came (a stop under `resumeGap`). |
| Budget | `VideoFrameScheduler.keptAheadBytes`, 12 MiB by default: about a screen of panel clips (160 px at most, a ring of three and one in flight, 0.4 MiB a clip) or three 512 px clips. Past it the clip away longest gives its frames up and comes back as under ticket 144 (its frame, a hold, then on). *Superseded by ticket 150*: 24 MiB, and a clip without its frames starts over. Memory pressure (`releaseIdle`) and a disposed paintable (`forget`) drop them. Dart heap, apart from the texture pool's `keptFrameBytes`. |
| Lottie | A lease that takes its kept texture back knows the frame on it, so it renders the next frame and not that one again (one wasted render and a doubled first frame before). |
| Playing images | The engine codec keeps its own position and the frame decoded ahead (the paintable holds its pixels and leases nothing), so a GIF or WebP that comes back shows its frame. `playbackResumed` now keeps how long that frame had been up and shows it only for the rest of its duration, not its whole duration again. |
| Kept frame against the one seen | In the device-shaped test the kept frame is the last one composited, before and after this change. On the device it read a few frames past the one seen at leaving. Not reproduced here; two candidates remain for the device check. A frame written in the frame the cell left (from the tick before layout, or a write landing after the last raster) is posted but never latched, and on return the producer queue shows it first: one frame, at most two. And a cell can be hidden from view while still inside the paint window, under something drawn over the grid, so it plays on unseen. Neither is a playback fault, and the fix keeps the sequence continuous from whatever frame the texture holds. |

## Amendment: a clip that cannot go on smoothly starts over

Native-media ticket 150. Device recording at 027d26f4, eight returns on the panel's GIF page: no long hold, but about 0.3 s after each return one step two to five times the steady one, a catch-up of two or three frames, in the chat too. Before ticket 144 those GIFs started over on return and looked smooth.

Bisected with a device-shaped test (`example/test/flicker/gif_return_test.dart`: a phone's 1080 x 2400 at 3x, a panel of three 360 px clips a row, its screen scrolled off and back; frame indices and clip ids stamped into the fake engine's pixels and read where the texture writer posts and where the atlas draws): 92940450 and 614e82d0 start over from the still and play 0, 1, 2 in step; c7211a1d (144) and 027d26f4 (148) come back on the frame left, hold it for 18 display frames at 10 fps and then step by four. The cause is ticket 148's budget against a phone's screen: three frames of a 360 px clip are 1.5 MiB, nine of them pass 12 MiB, so most clips came back without their decoded-ahead frames, and the ticket 144 path (hold, then skip) ran. Clips that leave after them take what is left. A texture that lost its kept frame did worse: the still for three posts, then a frame far ahead.

| Area | Decision |
| ---- | -------- |
| Going on | A lease of a clip that came back goes on from where it left only when the player still holds its decoded-ahead frames and the new lease shows the frame left on at once: its texture kept it (`FrameTextureLease.showsFrame`) or, without a texture, its slot did (`FrameAtlas.keepsFrame`, new). Otherwise the clip starts over from its first frame and every kept frame of the key is forgotten: the still shows, then 0, 1, 2. `_ClipPlayer.after` (go on without the ring) is gone. Starting over on a GIF loop of a few seconds reads as the loop wrapping; a hold and a skip read as a stutter. |
| Budget | `defaultKeptAheadBytes` is 24 MiB: a screen of GIFs on a phone (a dozen clips of up to 384 px, three frames each), as many clips as the texture pool keeps frames for (`keptFrameBytes`, 24 MiB). Past it, clips start over. |
| First frame on a fresh texture | A texture is shown after three posts of its lease (the producer queue may still hold an earlier holder's frames). A clip that starts over posts its first frame on the first tick and had nothing newer for the next two, so the texture showed only its third frame, after the still. The lease now posts its last frame again on each tick with no newer one until the texture is shown, so the texture shows the frame the clip is on (the player keeps that buffer, `_sentLast`, until a newer frame is sent or the texture is shown). A lease that moves from a slot to a texture gains the same: its slot holds its frame two display frames longer, not three of the clip's. |
| Image codec | Unchanged: the frame counter GIF and WebP played by `PlayingImagePaintable`, stopped 300 ms and 1 s and resumed, go on from the frame left, one at a time (`packages/image_decoder/test/frame_counter_return_test.dart`). |
| Measuring | The demo's frame counter clips (`example/assets/frame_counter/`, made by `example/tool/frame_counter.dart make`) carry their index in a binary bar; `dart run tool/frame_counter.dart read <recording>` prints, per clip and return, the frame left on, the first frame back and any step but one or frame held too long. |

## Amendment: a panel's strip holds while the panel is away (2026-11-10)

Native-media ticket 152. The covers of a pack strip are `ContentView`s, and a
view under a disabled `TickerMode` was hidden: as the panel moved out (its
shell's tickers off, ADR 028) each cover's lease was released and its frame
kept in the pool, under `keptFrameBytes`. The grid's cells are held over the
same span and keep their leases. With stickers playing in the chat, those the
panel covers leave the screen as it opens again, after the covers released
theirs, and their kept frames (4 MiB each at four buffers) pushed the covers'
out of the bound, oldest first: every reopen showed the covers' stills for
three posts. With nothing playing in the chat the bound was never reached.

| Area | Decision |
| ---- | -------- |
| View | `ContentView.holdsWhileTickersOff`: a disabled `TickerMode` holds the view (`AssetBinding.held`: frame on screen, lease kept) instead of hiding it. `ContentView.inView` hides a view out of its viewport whatever the tickers say. |
| Strip | `PanelStripCover` holds while the panel's tickers are off, and hides only a tab scrolled out of the strip, so the covers, like the grid's cells, come back on the textures they left on. |

## Amendment: a hidden panel gives its textures back (2026-11-12)

Native-media ticket 201, from the jank analysis of ticket 200: after heavy
panel use, the chat's first fling missed refreshes, most of them behind
raster-thread page uploads. A hidden panel's cells were held (*leases of a
kept panel*) and kept their textures, a texture per cell; the panel's warm
had destroyed the chat sticker's idle texture for room, and when the sticker
came back the budget held only leased textures and textures of the cells'
class. A 512 px sticker then played from a page slot, uploading the top half
of a 1024 px page, 2 MiB, on every frame. The proposal test
(`packages/lottie_decoder/test/playback/lottie_kept_panel_texture_test.dart`)
reproduces it at the default sizes and budgets.

| Area | Decision |
| ---- | -------- |
| Signal | A hidden panel is offstage *and* held. The presentation view hides the panel under a `Visibility` that keeps its state (`maintainState`, `maintainAnimation`: the strategy owns the tickers), so its content can read `Visibility.of`. The catalogue sets every binding invisible while it is false (`CatalogLeafBindingPool.offstage`); a held binding stays held. Tickers off alone (a panel moving in or out, a sheet over it) still mean held on screen. A bare `Offstage` says nothing: a pager's off-screen page is unchanged. |
| Leases | A kept lease whose paintable left the screen (`releaseUnlessPainted` after `kept`) is parked: it gives its texture back with `release(showing:)`, as a lease that ends does, and stays kept, with its slot if it has one. Its next want takes the texture back with `FrameTexturePool.leaseKept`, which hands out only that asset's own kept texture, shown at once with no render. Lottie and video alike. |
| Reshow | The panel shows again held (it moves in): the held paint wants the frame it was held on, the cell takes its kept texture back and composites it from the first frame (`example/test/flicker/hidden_panel_textures_test.dart`). Cells past `keptFrameBytes` (24 MiB, 24 cells of 1 MiB; the idle limit of 24 destroys the rest of the class's textures) play from page slots until textures are free: their still, then their frame on a slot. They never take a neighbour's kept texture (`lease` would hand one out when no plain idle texture is left). |
| Chat | The kept textures are idle: a warm of the chat's class makes room by destroying them, oldest first, as any idle texture of another class. The chat under a popup is held on screen and keeps its textures. |
| Strip | The strip's covers (`ContentView.holdsWhileTickersOff`, ticket 152) do not read `Visibility.of`: they keep their leases while the panel is hidden, small textures, so the grid's kept frames cannot push theirs out of the bound. |
| Pages | The 512 px class opens a page of one cell (`FrameAtlas.oneCellFrom`): a 512 px frame that plays from a page uploads 1 MiB a frame, not 2. The other classes keep pages of four. |
| Not changed | The pool's warm still waits for a scroll to end before it creates; whether that delays the chat's texture after a close is left to the device data. |
| Device check | Back from a hidden panel, the first chat fling should show no page uploads of the chat's 512 px stickers in the scroll lab's upload marks, and no growth of `warmsShortOfRoom`; the panel's reopen should show every cell within the budget on its frame at once. |
