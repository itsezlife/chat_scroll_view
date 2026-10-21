# ADR 022: Asset cache and media pipeline contract

`catalog_assets` is a host-created, app-wide cache that turns a content key and
an asset spec into an `AssetPaintable`. Fetching, decoding, playback and
budgets sit behind seams the host and adapter packages fill. Unicode glyphs
are one media form of that pipeline: a baked sprite on a glyph atlas page.

**Status**: Accepted  
**Date**: 2026-10-16  
**Amended**: 2026-10-18 (chat-polish-3, ticket 10): the pause policies of the reference desktop client reach the shared clock through one lifecycle seam (section *Amendment: pause policies*); `PlaybackPauseLayer` gains three values and the default pausing set is spelled out  
**Relates to**: [ADR 006](006-panel-catalog-viewport.md) (replaces its process-wide cache wording; the atlas amendment there is the panel-side view of this ADR), [ADR 020](020-package-topology.md), [ADR 021](021-content-identity-and-collections.md), [ADR 024](024-panel-catalog-seams.md)

## Decided

| Area | Decision |
| ---- | -------- |
| Paint surface | A binding yields an `AssetPaintable`: `paint(canvas, rect, context)` with tint, opacity and playback time in the context. The adapter picks the representation (decoded image or frame, vector composition, baked glyph sprite). The paintable has an optional **sprite capability**: an atlas page handle plus a source rectangle. A consumer that batches (the panel catalog viewport) draws every sprite of one page in one batched atlas draw; a paintable without a sprite paints itself. A placeholder paintable is always available and synchronous. |
| Glyph form | Unicode glyphs are the built-in glyph media form: a **baked sprite** on a **glyph atlas page**, never a paragraph at scroll time on baking platforms. Until its cell is baked the binding presents the placeholder (circle) with no time limit; once baked it is final and yields a sprite. The glyph set is what the data layer's glyph-support seam supplies; the atlas bakes the list it is planned with and does not detect missing glyphs. A platform that does not bake (web) selects a paragraph-painting strategy behind the viewport's painter seam, not a platform fork in the cache. There is no special path and no downcast. |
| Atlas ownership | A host or page plans and creates the glyph atlas. The atlas owns its **page residency**. The cache reaches it through one narrow seam, a glyph sprite source (`spriteOf`, `holdPageOf`, page listener) that the atlas implements and the host registers with the scope. The cache does not create atlases and does not know the planned glyph list. |
| Page residency | Pages are shared state, not binding state. A binding resolves to a sprite and takes a hold on the page at attach and releases it at detach; it never holds pixels. Hold counts belong to the holder, so evicting or clearing a cache entry under a live binding never changes a count. Static glyph pages are immutable once composed. A separate dynamic page pool for animation frames may be added later; it shares the sprite abstraction, not pages. Pages are 2048 x 2048 with a 2 px transparent gutter, and the baked glyph size is one tunable constant capped at 72 px. |
| Memory | Resident static pages stay within 64 MiB while the panel is open, except during a rebake, where the previous set stays resident until the swap (about twice that for a few seconds). Pages stay resident for a 60 s retention after the last hold ends and are all released at once on memory pressure, pinned or not; a released page is read back from the page store, one page per frame. |
| Bake | The baker rasterises glyphs on the root isolate behind a rasteriser seam, paced by a governor that adapts glyphs per frame (1 to about 16) to measured frame time. It bakes the page holding the visible band first, then the nearest pages, and composes strips into pages one page per frame. The host owns the pause signals (panel hidden, panel opening, scrolling including the fling); the bake only reads them. The glyph probe ([ADR 023](023-data-layering-and-persistence.md)) shares the bake pass, so no glyph is rasterised twice. |
| Persistence | Pages persist behind a page-store seam. The cache key is system emoji art version signal, screen density, baked cell pixel size, atlas layout version and a hash of the planned glyph list. An art or catalogue change keeps the old pages drawing while the new set bakes into a staged generation, then swaps every sprite at once. A density, cell-size or layout-version change discards them and shows circles. The art version signal is a pixel fingerprint of a few sentinel glyphs drawn by the bake's own rasteriser. Rasteriser and page store ship fakes in `testing.dart`. |
| Entry identity | Content key plus `AssetSpec`: pixel size at DPR, template or tint decode mode, and variant (first frame only or full). Surfaces are named presets of spec and profile owned by the host and packages. The old `keyboard` / `messages` enum is gone. |
| Behaviour | A per-attach `AssetProfile` (animate, loop, autoplay first frame, corner radius). It does not split cache entries. |
| Attach | `attach(key, spec, profile)`. An unknown descriptor sends the core to the host `ContentResolver`; readiness stays `none` until it resolves. |
| Readiness | Staged `none`, `placeholder`, `firstFrame`, `full`, each with `isFinal`. There is no visible failed stage. A failed fetch or decode clears the in-flight record and leaves readiness where it was, so the cell keeps its placeholder, including offline, until it detaches. Retry happens on the next attach, on the host's connectivity-restored signal for still-attached bindings, and through explicit `retry()`. The fetcher reports a failure class (transient or permanent) so the core knows whether connectivity-restored is relevant; neither class is shown as failed. Cancellation is not a failure. The last error is exposed for logging only. The paintable draws the best stage available; painters use the stage only for crossfade, and an instant memory hit has none. |
| Orchestration | The core owns in-flight dedupe by entry identity, cancel when the last binding leaves, priority classes (placeholder, visible, preload) and concurrency caps. |
| Seams | A host `ContentFetcher` (descriptor to bytes or file) owns network, provenance refresh and the disk tier. Decoders are registered per media form (still, animated image, vector animation, video, glyph) from adapter packages: fetched data plus spec to paintable with stages. |
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
| Six-level reason hierarchy (`Any`, `InlineResults`, `TabbedPanel`, `Layer`, `RoundPlaying`, `MediaPreview`): a surface pauses under a reason above its own, so the open panel keeps playing while the chat behind it stops | Only the `Any` and `Layer` equivalents: app inactive/hidden, and a host overlay. An open emoji panel, a sticker preview or a playing round video do not pause the chat | Chat and panel share one clock, so a global layer cannot say "the chat but not the panel"; a host that wants it feeds `ChatEmojiBody.isActive` |
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
