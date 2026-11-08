# ADR 022: Asset cache and media pipeline contract

`catalog_assets` is a host-created, app-wide cache that turns a content key and
an asset spec into an `AssetPaintable`. Fetching, decoding, playback and
budgets sit behind seams the host and adapter packages fill. Unicode glyphs
are one media form of that pipeline: a baked sprite on a glyph atlas page.

**Status**: Accepted  
**Date**: 2026-10-16  
**Amended**: 2026-10-18 (chat-polish-3, ticket 10): the pause policies of the reference desktop client reach the shared clock through one lifecycle seam (section *Amendment: pause policies*); `PlaybackPauseLayer` gains three values and the default pausing set is spelled out  
**Amended**: 2026-11-06: the dynamic page pool, the renderer seam and the frame cache for native animated media ([ADR 042](042-native-media-decoding.md); section *Amendment: dynamic frame pages*)  
**Amended**: 2026-11-08: a playing asset may be shown through a platform texture, a third paint capability next to `paint` and the sprite, with the dynamic pages as the fallback ([ADR 043](043-platform-texture-frames.md))  
**Amended**: 2026-11-09 (native-media-ffi, ticket 85): an entry below its first frame shows the best stage of a sibling entry, the same content at another spec (section *Amendment: sibling stages*)  
**Amended**: 2026-11-09 (native-media ticket 87): a binding can be **held** by its surface, and nothing plays while the panel moves (section *Amendment: held surfaces and the panel's motion*)  
**Amended**: 2026-11-09 (native-media ticket 90): content that arrives after the attach fades in on every surface, a texture included (section *Amendment: arrival fade*)  
**Amended**: 2026-11-09 (native-media ticket 91): a host keeps its media disk tiers in one store, kept by last use rather than by a budget per tier (section *Amendment: one media disk store*)  
**Amended**: 2026-11-09 (native-media ticket 94): the fetcher reports the bytes of a download and a binding exposes the fraction, null when nothing downloads; the download indicator shows only then (section *Amendment: download progress*)
**Relates to**: [ADR 006](006-panel-catalog-viewport.md) (replaces its process-wide cache wording; the atlas amendment there is the panel-side view of this ADR), [ADR 020](020-package-topology.md), [ADR 021](021-content-identity-and-collections.md), [ADR 024](024-panel-catalog-seams.md)

## Decided

| Area | Decision |
| ---- | -------- |
| Paint surface | A binding yields an `AssetPaintable`: `paint(canvas, rect, context)` with tint, opacity and playback time in the context. The adapter picks the representation (decoded image or frame, vector composition, baked glyph sprite). The paintable has an optional **sprite capability**: an atlas page handle plus a source rectangle. A consumer that batches (the panel catalog viewport) draws every sprite of one page in one batched atlas draw; a paintable without a sprite paints itself. A batching consumer groups sprites by the page **image**, never the page number, because the page numbers of a glyph atlas and a frame pool overlap. A paintable that plays exposes its sprite only after it was advanced, so the optional `advancePlayback(context)` hook (a no-op by default; `AssetBinding.advancePlayback()` supplies the context a paint would) lets a batching consumer drive playback without calling `paint`; `paint` does the same first, so a consumer that paints needs no call. A placeholder paintable is always available and synchronous. |
| Glyph form | Unicode glyphs are the built-in glyph media form: a **baked sprite** on a **glyph atlas page**, never a paragraph at scroll time on baking platforms. Until its cell is baked the binding presents the placeholder (circle) with no time limit; once baked it is final and yields a sprite. The glyph set is what the data layer's glyph-support seam supplies; the atlas bakes the list it is planned with and does not detect missing glyphs. A platform that does not bake (web) selects a paragraph-painting strategy behind the viewport's painter seam, not a platform fork in the cache. There is no special path and no downcast. |
| Atlas ownership | A host or page plans and creates the glyph atlas. The atlas owns its **page residency**. The cache reaches it through one narrow seam, a glyph sprite source (`spriteOf`, `holdPageOf`, page listener) that the atlas implements and the host registers with the scope. The cache does not create atlases and does not know the planned glyph list. |
| Page residency | Pages are shared state, not binding state. A binding resolves to a sprite and takes a hold on the page at attach and releases it at detach; it never holds pixels. Hold counts belong to the holder, so evicting or clearing a cache entry under a live binding never changes a count. Static glyph pages are immutable once composed. A separate dynamic page pool for animation frames may be added later; it shares the sprite abstraction, not pages. Pages are 2048 x 2048 with a 2 px transparent gutter, and the baked glyph size is one tunable constant capped at 72 px. |
| Memory | Resident static pages stay within 64 MiB while the panel is open, except during a rebake, where the previous set stays resident until the swap (about twice that for a few seconds). Pages stay resident for a 60 s retention after the last hold ends and are all released at once on memory pressure, pinned or not; a released page is read back from the page store, one page per frame. |
| Bake | The baker rasterises glyphs on the root isolate behind a rasteriser seam, paced by a governor that adapts glyphs per frame (1 to about 16) to measured frame time. It bakes the page holding the visible band first, then the nearest pages, and composes strips into pages one page per frame. The host owns the pause signals (panel hidden, panel opening, scrolling including the fling); the bake only reads them. The glyph probe ([ADR 023](023-data-layering-and-persistence.md)) shares the bake pass, so no glyph is rasterised twice. |
| Persistence | Pages persist behind a page-store seam. The cache key is system emoji art version signal, screen density, baked cell pixel size, atlas layout version and a hash of the planned glyph list. An art or catalogue change keeps the old pages drawing while the new set bakes into a staged generation, then swaps every sprite at once. A density, cell-size or layout-version change discards them and shows circles. The art version signal is a pixel fingerprint of a few sentinel glyphs drawn by the bake's own rasteriser. Rasteriser and page store ship fakes in `testing.dart`. |
| Entry identity | Content key plus `AssetSpec`: pixel size at DPR, template or tint decode mode, and variant (first frame only or full). Surfaces are named presets of spec and profile owned by the host and packages. The old `keyboard` / `messages` enum is gone. |
| Behaviour | A per-attach `AssetProfile` (animate, loop, autoplay first frame, corner radius). It does not split cache entries. |
| Attach | `attach(key, spec, profile)`. An unknown descriptor sends the core to the host `ContentResolver`; readiness stays `none` until it resolves. |
| Readiness | Staged `none`, `placeholder`, `firstFrame`, `full`, each with `isFinal`. There is no visible failed stage. A failed fetch or decode clears the in-flight record and leaves readiness where it was, so the cell keeps its placeholder, including offline, until it detaches. Retry happens on the next attach, on the host's connectivity-restored signal for still-attached bindings, and through explicit `retry()`. The fetcher reports a failure class (transient or permanent) so the core knows whether connectivity-restored is relevant; neither class is shown as failed. Cancellation is not a failure. The last error is exposed for logging only. The paintable draws the best stage available; painters use the stage only for crossfade, and an instant memory hit has none (*Amendment: arrival fade*). A thumbnail (the `placeholder` stage) that a better stage replaces is kept by the entry for the bindings that were attached while it showed: the surface fades the content in over it (`AssetBinding.paintStandIn`), and it is disposed when every such binding released it (`releaseStandIn`, or a paint of the content at full opacity, or a detach). The thumbnail is decoded small and blurred once (`MiniThumbnail`), never blurred per frame. |
| Orchestration | The core owns in-flight dedupe by entry identity, cancel when the last binding leaves, priority classes (placeholder, visible, preload) and concurrency caps. |
| Seams | A host `ContentFetcher` (descriptor to bytes or file) owns network, provenance refresh and the disk tier (a fetched file kept under its content identity, not its URL, so a later launch finds it without asking the network; the host keeps it, see *Amendment: one media disk store*). A host may turn every disk tier off at once (its fetchers' files, the frame cache's folder, the glyph atlas cache), for tests and measured runs: each then keeps memory only, as on the web. Decoders are registered per media form (still, animated image, vector animation, video, glyph) from adapter packages: fetched data plus spec to paintable with stages. |
| Playback | One shared clock in the core. Per-binding animate gating combines with global pause layers (route moving, fast scroll, low power, surface hidden, app inactive, reduced motion, overlay shown) under a default policy; the fps cap derives from spec size. The app-level layers come from one `PlaybackActivity` (amendment below), not from per-widget flags. The host feeds a connectivity-restored signal; the core never touches the network. Paintables never schedule timers. |
| Budgets | Byte-accounted tiered LRU with host-configurable budgets and defaults. Entries with live bindings are pinned. Unattached ready entries stay until pressure. `clearAll` and a memory-pressure hook exist. Eviction never invalidates a live binding. Releasing by distance is the surface's job, through detach. |
| Scope | One host-created instance provided through a widget scope and by explicit injection. No static singleton. |
| Threading | Decoders may use isolates or native threads. The core is single-threaded on the UI isolate; listener callbacks and painting happen there. |
| Test seam | The package ships in-memory adapters (`FakeFetcher`, `FakeDecoder`, manual clock) and contract suites every adapter must pass. Production code never downcasts. |

## Why

- Telegram's pipeline has five layers with cache identity that includes size and spec, playback gating, byte budgets, and no retained failure. Android and iOS show the placeholder indefinitely when a load fails; offline cells keep it.
- The old cache exposed only readiness, so consumers downcast to the in-memory implementation. Evicting an entry could corrupt a live binding's reference count. Each panel page built its own cache, contradicting ADR 006.
- The system emoji font rasterises each colour glyph on the raster thread the first time it appears, and on every frame on the Skia renderer. Measured on a 120 Hz phone, the first catalogue pass dropped 21 of 455 frames and a paced offscreen warm-up did not remove the cost. Baking pays it once, paced and persisted.
- A sprite is a page handle plus a rectangle, so the same capability can later carry animated media through a dynamic page pool without a second engine.
- Sharing page residency between the atlas and the bindings keeps hold counts and the memory ceiling in one place, and keeps `panel_catalog` ignorant of atlas types: it sees an `AssetPaintable` and its sprite capability.

## Rejected

| Alternative | Why not |
| ----------- | ------- |
| Decoded `ui.Image` per tick as the only surface | Vector animation becomes bitmaps with no batching across leaves; `ImageProvider` or a widget per item does not fit a custom render object |
| Closed surface-class enum; key-only identity | It cannot express DPR and duplicates identical pixels |
| Three-state readiness; a visible failed stage (sticky or soft with bounded retry) | Telegram never shows one; offline cells keep their placeholder |
| One loader doing fetch and decode | Every codec adapter would reimplement fetching and the disk cache |
| Host-supplied finished paintables | Everyone reimplements dedupe, cancel and priority |
| Per-surface tickers or self-scheduling paintables; no budgets; count-based LRU | Unbounded memory and uncoordinated animation |
| Static singleton; per-surface instances | Hidden global state, or duplicated pixels |
| Unicode as a synchronously final paragraph paintable | First sight of each glyph costs raster time inside the frame |
| Per-binding ownership of glyph pixels | Eviction could corrupt a live binding, and one page could not be drawn in one batch |
| Atlas created and owned by the cache | The glyph list and the pause signals belong to the host and page; the cache would need data-layer knowledge |

## Related

- Panel-side view and acceptance: [ADR 006](006-panel-catalog-viewport.md) (amendment); cache and invalidation QA: [qa-glyph-cache.md](../panel-catalog/qa-glyph-cache.md)
- Glossary: [Content and assets](../content/CONTEXT.md), [Panel Catalog](../panel-catalog/CONTEXT.md) (glyph atlas group)

## Amendment: glyphs that join after the plan

An atlas draws only what it was planned with, and its plan cannot change in
place. Planning the whole atlas again for every new glyph (a tone chosen for the
first time) re-baked the catalogue for one emoji, re-keyed the persistent cache,
and dropped from the new plan the glyphs the grid no longer showed while a
composer still drew them, as placeholders, until the panel was reopened. The
reference clients draw a new emoji at once and never unload one in use.

| Area | Decision |
| ---- | -------- |
| Waiting | The glyph sprite source answers `waitsForSprite(glyph)`: whether a sprite for it is on its way. An atlas says yes for every glyph it planned (circle until baked, the rule above); a glyph no source waits for is drawn as text by its binding (`firstFrame`), so a glyph outside every plan is never a circle for good. |
| Layers | `LayeredGlyphSource` is one source over several: the first layer is the background bake and decides `waitsForSprite`; layers added later bake on demand, and a surface draws their glyphs as text until their sprite exists. Sprites and holds come from the first layer that has the glyph; page listeners hear every layer and each add or remove. It owns no layer. |
| Page indices | A sprite's page index names one page image across the whole source, because a surface batches its draws by it. Every layer numbers its pages from 0, so the layered source gives each layer a block of indices of its own (the first layer's starts at 0) and moves its sprites and page signals into it. Without the blocks a glyph of a later layer was cut from the first layer's page of the same index: a new tone showed the first glyph of the catalogue. |
| Growth | The page's atlas host keeps the first atlas and, for a plan with glyphs no atlas holds, plans an atlas of just those glyphs (an in-memory store of its own, never the persistent cache) and adds it as a layer. Nothing baked is baked again, the persisted pages keep their key, and no glyph ever leaves the source while the host lives. Only a density change plans the first atlas again, for every glyph of every layer. |
| Activity | Motion and the visible band reach every layer, including one added while the motion lasts. |

## Amendment: pause policies

The reference desktop client has no single pause switch: one ambient bit
("any pause reason is set, or the main window is not active") reaches every
sticker, custom emoji, spoiler and streamed GIF; eleven power-saving flags are
forced on together by the OS battery saver; and nothing animates that is not
painted. The workspace had the sink (the shared clock and its layers) but only
`hidden` was fed into it. Research: `.scratch/chat-polish-3/research/07`.

| Area | Decision |
| ---- | -------- |
| Seam | `PlaybackLifecycleSource` (`state`, a `Listenable`) is the one platform input; `WidgetsPlaybackLifecycleSource` is the adapter over the widgets binding, `ManualPlaybackLifecycleSource` the fake, `PlaybackLifecycleSourceContract.run` the suite ([ADR 030](030-testing-policy.md)). `PlaybackActivity(clock:, lifecycle:, lowPower:, reducedMotion:)` maps the inputs onto the clock's layers. A host creates one per scope and disposes it; no widget takes a pause flag. |
| Lifecycle mapping | `resumed` and an unknown state (`null`, or a first `detached`): nothing. `inactive` (window or app lost focus; on the web a blurred tab): `appInactive`. `hidden`, `paused`, `detached` (minimised, hidden, another desktop): `appInactive` and `surfaceHidden`, at once. The platform delivers `resumed -> hidden` as `inactive`, `hidden`; the clock stops its frames once. |
| Grace | `PlaybackActivityPolicy.unfocusedGrace` and `focusedGrace`, both zero: the reference client recomputes its window state one event-loop turn after the window event; its 1 s and 5 s timers only back that up and feed the "online" status. A host may debounce; the opposite change cancels a pending one; hiding never waits. |
| Layers | New: `appInactive`, `reducedMotion`, `overlayShown`. `PlaybackPolicy.standardPausingLayers` is spelled out (every layer but `reducedMotion`); a layer added later pauses only once someone decided it should. Reduced motion is reported and does not stop playback: the reference client does not read the setting, animated emoji are content, and chrome motion and the spoiler stillness already follow `MediaQuery.disableAnimations`. A host adds it to `pausingLayers` to make it stop playback. |
| Low power | Host-fed `ValueListenable<bool>`. The SDK reports no battery state, `battery_plus` documents battery-saver detection for Android, iOS, macOS and Windows only, and a library that chose a plugin would impose it on every host. The reference client's rule (macOS Low Power Mode or a critical/low battery, Windows Battery Saver, Linux power-saver profile, a user override) is the host's to implement. |
| Overlays | `PlaybackActivity.holdOverlay()` returns a hold; `overlayShown` is set while any hold is open, so nested overlays do not clear each other. The reference client pauses the chat under any box layer; `TickerMode` does not reach a non-opaque route. The host calls it per route (the example does, from a `NavigatorObserver`). |
| Resume | Freeze and continue, never rewind and never jump to the live position. `PlaybackClock.now` stands still while paused and jumps once on the first frame after; the frame-sequence paintable shows its next frame at once and restarts its timing, without skipping or ending a pass early, and a custom paintable must do the same. The spoiler dust adds up the time it is told and cuts out a pause, so its phase goes on; the fork derives the dust frame from the time alone. Pausing never touches the reveal state of a spoiler. |
| Ownership | `PlaybackActivity` owns `appInactive`, `surfaceHidden`, `lowPower`, `reducedMotion` and `overlayShown`; `routeMoving` and `fastScroll` stay the host's. `dispose` clears what it set and nothing else, and disposes none of its inputs. |

### What the reference client does that is not replicated

| Reference behaviour | Here | Why |
| ------------------- | ---- | --- |
| Six-level reason hierarchy (`Any`, `InlineResults`, `TabbedPanel`, `Layer`, `RoundPlaying`, `MediaPreview`): a surface pauses under a reason above its own, so the open panel keeps playing while the chat behind it stops | The `Any` and `Layer` equivalents (app inactive/hidden, a host overlay) as clock layers, and `TabbedPanel` as a hold of the chat's bindings (amendment of 2026-11-09). A sticker preview or a playing round video do not pause the chat | Chat and panel share one clock, so a global layer cannot say "the chat but not the panel"; a surface's own hold can |
| Round video message exempt from the window-inactive pause | None | No round video in the library |
| Eleven `PowerSaving` flags, the "Power usage" screen, per-feature autoplay and loop settings | One `lowPower` layer; the host maps its settings to `AssetProfile`, `ChatStickerPlayback`, `MarkdownSpoilerController.animate` and `ChromeMotionSpeed` | Product settings, not a contract |
| Spoiler reveal hidden again by a jump to a message in the same section (`hideShownSpoilers`) | Not replicated; a chat switch still re-hides, because the controller lives with the chat screen | An explicit re-hide rule is a product choice; nothing here reveals or hides on a pause |
| Unload of heavy parts beyond two pages of the viewport; unpainted spoiler stop after 1 s, unpainted clip stop after 200 ms | Already structural: a binding leaves the clock when not visible, and the clock asks for frames only while a target is registered | Pull ticking |
| Read-tracking gates (window exposed, user idle 30 s) for effects on read | None | Not an animation rule |
| Occlusion by another window | `hidden` on macOS only (the embedder reports full occlusion there); a covered window is otherwise only `inactive` when focus moved | The embedder's report is the signal; the reference client's active bit has the same blind spot |
| Screen lock and sleep | Fall out of `inactive` and `hidden`; no hook | The reference client has none either |
| Stories, calls, media viewer rules | None | Not in the library |

Not verified on a device: the pause behaviour on a real desktop (the tests use
fake lifecycle sources and a manual frame source), including whether the
embedder delivers `inactive` and `hidden` as the engine sources say.

## Amendment: held surfaces and the panel's motion

Native-media ticket 87. The reference desktop client paints its emoji panel
from a snapshot while it shows or hides (`TabbedPanel::grabForAnimation`,
children hidden until `_a_show` ends) and, while the panel is shown, sets
`GifPauseReason::TabbedPanel`, which pauses the chat's animations below it.
The reference mobile client locks notifications during the panel's animation
(`AnimationNotificationsLocker` in `ChatActivityEnterView`).

| Area | Decision |
| ---- | -------- |
| Held binding | `AssetBinding.held` (default false) is one surface's hold: the binding leaves the clock as an invisible one does, but stays shown (its demand stays visible) and paints at the clock's time when the hold began, so a repaint shows the same frame. Releasing it plays on from there. `visible` stays "not on screen", which lets leases go; `held` is "on screen, still". |
| Keeping the frame | `AssetPaintable.keepFrame(keep:)`, a no-op by default, is set by the entry while any of its bindings is held, and carried to a paintable that replaces the stage. A paintable that leases where its frame lives keeps that lease through the idle sweep, where it is, rendering nothing; see [ADR 043](043-platform-texture-frames.md). Without it a texture given back after an idle period would be written by its next holder under the held surface's layer. |
| Host input | `ContentEmbed` and `ContentEmbedResolver` take `held:`, a listenable the host feeds to every embed of one surface; the embed follows it and never disposes it. |
| Panel motion | Hosts set `PlaybackPauseLayer.routeMoving` while the panel presentation moves in or out (`PanelVisibility.isMoving`, every kind), so the panel's content and the chat hold: no tick, no decode, no upload; every surface keeps its frame. The example's `PanelPlaybackHold` does it from the presentation's state and clears only what it set. |
| Popup | While an anchored popup is on screen (showing to hidden), the host holds the chat's embeds; the panel's own content plays. A dock and a keyboard panel at rest hold nothing. |
| Shared entries | A held surface and a playing one that show the same entry share one paintable: the held one keeps its frame on pages (its picture keeps the image) but shows the live frame through a shared texture. Accepted: the panel and the chat rarely show one entry at one size. |

## Amendment: dynamic frame pages

The first decision table anticipated "a separate dynamic page pool for
animation frames" sharing the sprite abstraction. This section makes it a
contract for the native engines of [ADR 042](042-native-media-decoding.md).
Evidence and open items are in that ADR.

| Area | Decision |
| ---- | -------- |
| Surface | An animated asset owns a **slot** on a shared **dynamic page**. A worker renders every active slot in one batch call per tick; the pool uploads one image per page that changed. The paintable exposes the sprite capability: the chat paints it with a rectangle draw from the page, the panel batches draws per page. Static glyph pages and dynamic pages share the sprite type and nothing else: separate pools, separate budgets. |
| Renderer seam | `catalog_assets` defines an engine-agnostic seam: given slots, frame times and sizes, write premultiplied pixels into page memory. A decoder adapter implements it; the pool, the slot allocator and page residency stay in `catalog_assets`, which depends on no native code. |
| Time | A paintable plays from its own first animating paint, by adding up the clock's steps between paints (a step over 500 ms, or backwards, adds nothing: pause is freeze-and-continue), as `PlayingImagePaintable` does. Stickers therefore keep the phase of their first paint, not one global phase. The worker renders one to two frames ahead. A frame that is late never blocks painting: the slot keeps its last good frame. Until a first frame exists the first-frame still or the placeholder shows. |
| Budget | The pool has its own host-configured byte budget (default 48 MiB), apart from the 64 MiB of static glyph pages, counted in **bytes**: a page opens when its bytes still fit. A page holds one size class (64, 128, 256, 384 or 512 px cells) and its side is **twice the class edge**, so a page has at most four cells: 128, 256, 512, 768 and 1024 px, 64 KiB to 4 MiB. The 384 class (amended 2026-11-09) holds a chat sticker of 112 pt at 3x (336 px) and a GIF row at 3x (300 px), which the 512 class held at 1.8 to 2.9 times their pixels, as the reference client renders a sticker at its view's pixel size. Evidence: the playback benchmark (`LOTTIE_PLAYBACK_BENCH=1`, ticket 34) showed that one page size for every class uploaded a whole 1024 px page (4 MiB) every tick for one 128 px sticker, 64 times the bytes that changed, because `decodeImageFromPixels` has no partial update; with pages by class one sticker uploads 256 KiB (4x) and N stickers upload ceil(N/4) small pages (1x from eight stickers). The price is more images and more upload calls for many stickers (32 stickers are eight uploads, 0.77 ms against 0.37 ms for one 4 MiB upload in the headless engine). A slot carries its page side, and the page memory makes each page at the side it is first asked for, so every consumer computes strides from the slot alone. A budget below the smallest page is an error, and a class whose page is above the remaining budget finds the pool full. A page that loses its last slot goes back to the budget and its index is never reused. A slot is held while its paintable is painted: the scheduler releases it after it is unwanted for between one and two idle periods (default 1 s) by one sweep timer that exists only while leases exist, never by a timer of the paintable; a released slot stays in the pool idle and evicts least-recently-used. A full pool shows the newest asset's first-frame still instead of animating: never an error, never a visible failed stage. Pages release on memory pressure like glyph pages. |
| Frame cache | After the first render, each frame is stored lz4-compressed, keyed by the SHA-256 of the file's bytes, the **display** pixel size the frames are rendered at (not the source size) and `LottieNativeVersion.engine`, so an engine update never replays frames the old engine drew; above 512 x 512 the cache is skipped. The RAM tier keeps whole animations, least recently used first; the disk tier counts against a host-configured budget with least-recently-used eviction, or has none when its folder is in the host's media store (*Amendment: one media disk store*). The cache holds opaque bytes: the renderer, not the cache, knows the codec, and the render isolate owns it (`renderCapturing` returns a rendered slot compressed, `restore` decompresses into one), so there is no separate cache isolate. On the web the cache is memory only: a pixel engine has no codec and the browser gives no directory (`FrameCache(directoryPath:)` takes null there). |
| Fps | The fps cap derives from the spec's pixel size, as above. An asset authored at 60 fps and shown small plays at the cap, not at 60. |
| Video | Video GIFs and video stickers write display-size BGRA into the same slots and pages. A shader-side YUV upload is a later optimisation behind the seam. |
| Rest | `loop` false holds the rest frame and `restart()` replays from frame 0; `animate` false uses the first-frame stage only: the existing paintable contract, unchanged. |
| Size cap | An animation whose spec is larger than the largest size class (512 px on the longer side) shows its still: the decoder reports the first frame, rendered at the cap, as `firstFrame` and again as `full`, and frees the native handle. The reference clients skip the frame cache and cap the render at 512 likewise. |
| Failure | A native library that fails its start-up probe leaves its media form without a decoder; the entry stays at its placeholder. An input the engine's checks reject ends in `AssetProgress.fail`. Both follow the failure rule above. |

## Amendment: sibling stages

Entries stay keyed by content and spec, so the same content at two sizes is
two decodes. A GIF picked from a panel cell was attached again at the
message's size, a new entry at `none`, and the message drew the placeholder
rectangle for a frame or more before the GIF it had just shown in the cell.
The rule "the paintable draws the best stage available" now reaches across
specs.

| Area | Decision |
| ---- | -------- |
| Sibling | An entry of the same key and decode mode at another pixel size or variant. A template decode is alpha only, so it is never a sibling of an original one. |
| Borrow | While a binding's entry is below `firstFrame` (as its profile shows it), the binding paints the sibling with the best stage above its own, the larger decode on a tie, into its own rectangle with its own profile (fit, corner radius, playback). Its readiness is that stage, never final. It borrows anew when its entry or a sibling advances, and gives the sibling back once its entry reaches `firstFrame` or it detaches. The switch to its own picture is instant: there was no placeholder to fade over, so the entry's thumbnail is not kept as a stand-in for a binding that was borrowing. |
| Pinning | A borrowed sibling is pinned like a bound entry, so the budget, `clearAll` and memory pressure never dispose a paintable on screen. Given back, it returns to the budget, or is dropped at once if it has no stage worth keeping. |
| Playback | A borrowed paintable that plays is advanced by the borrowing binding as its own, sharing one playback with the sibling's bindings (the rule for bindings of one entry), and keeps its page slot or texture leased while it is painted; the lease ends by the usual idle sweep once the binding draws its own entry. |
| Not decided | A synchronous first stage from a decoded sibling (scaling its pixels into the new entry) is not done: the borrow already removes the placeholder, and a rescale would cost a decode-sized copy on the UI isolate. |

## Amendment: arrival fade

The readiness row left the crossfade to each painter, and only the catalogue
viewport drew one; a `ContentView` (a GIF cell, a message's sticker) cut from
the stand-in to the content. The reference client fades every image that is
not a memory hit (`ImageReceiver.draw`, 150 ms `DEFAULT_CROSSFADE_DURATION`),
so this is now one rule for every surface.

| Area | Decision |
| ---- | -------- |
| When | A content stage (`firstFrame` or `full`) that reaches a binding after its attach, fetched or decoded, fades in from transparent to opaque over 150 ms, linear, from the first frame that draws it. A binding whose entry had content at the attach (a memory hit, including one a producer serves synchronously inside the attach, and a sibling's stage borrowed at the attach, *Amendment: sibling stages*) shows it at once, so a surface built again over loaded content, such as a cell scrolled back into view or a page shown again, never fades. A glyph never fades: it is text, not an image that arrives. |
| Beneath | The kept thumbnail (`paintStandIn`) stays opaque under the rising content and is released once the content is opaque, as before; with no thumbnail the scope's placeholder fades out as the content rises. |
| Texture | A texture layer cannot fade itself, so during the fade it is pushed under an opacity layer (`AssetTextureLayer.composite` with the fade's opacity); the stand-in is drawn on the canvas first, beneath it. |
| Where | The fade is the surface's paint over its binding, read through one internal rule (`AssetFade`, the clock being the frame time): `ContentView` and the catalogue viewport (`CatalogBoundLeaf`, same 150 ms) apply it. `ContentEmbed` (glyphs and stickers inside text) does not yet. A surface's own entrance (the GIF page's cells fading in as a page arrives) is separate and composes with it. |

## Amendment: one media disk store

Each disk tier kept its own budget (a host's fetcher files per kind, the frame
cache's folder), so a host tuned three numbers and a tier could be full while
another sat empty. The reference clients keep one cache for all media: no size
limit by default, and media unused for a keep period (one month by default)
deleted; a total limit is an option the user sets.

| Area | Decision |
| ---- | -------- |
| Store | A host keeps its animated media (fetched stills and clips, rendered frame files) in one disk store: a folder whose tiers each keep their files in a folder of it. A tier reads and writes its own files, atomically as before, and stamps a file's time when it uses one; the store only removes. The glyph atlas cache is not media and stays apart. |
| Keeping | The store removes every file no tier used for the keep period (default one month, by last use). With a total size limit (default none), it then removes the least recently used of the rest, across the tiers, until they fit, sparing a file used within the last minute (a write landing, a read under way). Both are the host's settings. A tier in the store keeps no budget of its own: `FrameCache(diskBudgetBytes: null)`. |
| Eviction | A sweep runs at start and periodically (hourly), off the frame path (its own isolate), one at a time. No tier waits for one: a file removed under a read is a miss, fetched or rendered again. |
| Switch | Turning every disk tier off (above) turns the store off: it is neither used nor swept. |

## Amendment: download progress

The readiness row reported stages and no fractions, so a loading GIF cell drew
an arc of a fixed quarter turning from wherever the clock stood, for any
content without a frame, including content read from the disk tier. The
reference client draws its loader only while the file downloads
(`isLoading || !fileExist`), from the file's known progress, and nothing for a
cached file.

| Area | Decision |
| ---- | -------- |
| Fetcher | `FetchRequest.onProgress(received, total)` (total null when the source announces none). A fetch that transfers its part reports once when the transfer starts and as bytes arrive; a part served from a cache the host keeps (memory or disk) is not a transfer and is never reported. A transfer shared by several requests reports to each, a late one first hearing where it stands. A response that comes whole (a replayed recording) may report in one step. |
| Pipeline | Relays the **content** part's fraction to the entry (`AssetProgress.download`), received over total, 0 while the total is unknown, and 1 once the fetch completes after a reported transfer. A thumbnail's transfer is not relayed: it is a stand-in, not the download a surface shows. A decoder that opens its own stream may report through the same call. |
| Binding | `AssetBinding.downloadProgress`: the entry's fraction from the first report until the attempt ends (its final stage, a failure or a cancel), signalled on change; null otherwise, so a memory hit, a disk hit, a glyph and a detached binding read null. A borrowed sibling stage (*Amendment: sibling stages*) does not bring the sibling's download along. A failed download clears it: the cell keeps its placeholder with no loader, as for any failure. |
| Indicator | `RadialProgress` is one stateful indicator per download, a port of the reference's `MediaActionDrawable` in its `ICON_EMPTY` state (a bare arc in the disc, no cross): it starts at 112 degrees with the progress first seen shown at once, sweeps `max(4, 360 * shown)` degrees, turns 360 degrees per 2500 ms with a frame counting at most 17 ms, eases a higher fraction from the arc shown over 200 ms with a decelerate curve, and shows a lower one at once. |
| Where | `ContentView` (`loadingRadius`) and the catalogue viewport's GIF leaves draw it only while the binding's download is non-null and the content has no frame; each keeps its own indicator (the viewport beside each binding) and drops it when the download ends. |

