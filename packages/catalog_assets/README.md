# catalog_assets

The asset cache core of the catalogue packages: what a surface binds to, how
far an asset has come, how long it is kept, what advances its animation, and
the baked glyph atlas that unicode glyphs are drawn from.

Entry points: `catalog_assets.dart` (the cache core), `glyph_atlas.dart` (the
atlas: planning, baking, paging), `testing.dart` (opt-in fakes and contract
suites). No scroll-viewport RenderObject dependency. Depends on
`content_model` (`ContentKey`) and, for change notification, the pure-Dart
`package:listen` (`Listenable`).

## The cache core

A host creates one `AssetCacheScope` and hands it to the surfaces that draw
content. A surface calls `attach(key, spec, profile)` and gets an
`AssetBinding`; it reads `binding.readiness` and `binding.paintable`,
repaints when the binding signals, and calls `detach()` when it stops showing
the content.

| Type | Role |
| --- | --- |
| `AssetCacheScope` | Host-created instance (no static singleton); owns entries, the default clock and placeholder, and nothing it was handed. `attach`, `clearAll`, `connectivityRestored`, `dispose`; `glyphSource`, `budgets` |
| `AssetSpec` | What is decoded: pixel size at density, decode mode (`original` / `template`), variant (`full` / `firstFrame`). With the `ContentKey` it is the entry identity |
| `AssetProfile` | Per-attach behaviour: animate, loop, rest frame (`AssetRestFrame`, first or last, read when it does not loop), autoplay first frame, corner radius. Never splits an entry |
| `AssetBinding` | One surface's live attach: `readiness`, `paintable`, `lastError`, `isPlaying`, `playback` (`AssetPlayback`: idle, playing, ended), `replay()`, `visible`, `paint`, `retry`, `detach`; a `listen` `Listenable`. A profile that does not loop plays one pass, holds its rest frame and costs no ticks; `replay()` plays another and returns false while a pass runs. Surfaces of one entry share one playback |
| `AssetPaintable` | What a binding yields: `paint(canvas, rect, context)`, `isAnimated`, `isHolding` / `restart()` for a playback that stopped on its rest frame, and an optional `sprite` (atlas page + source rectangle) for surfaces that batch |
| `AssetStage` / `AssetReadiness` | `none`, `placeholder`, `firstFrame`, `full` and `isFinal`. There is no failed stage |
| `AssetProducer` (seam) | Makes the paintables of entries: `produce(request, progress, demand)` returns an `AssetTask`; reports stages, failures and cancellation through `AssetProgress`. `AssetPipeline` is the fetching and decoding implementation |
| `AssetCacheBudgets` | Byte budgets of the unattached entries per tier (`still`, `animated`); documented defaults |
| `PlaybackClock` / `PlaybackPolicy` | One shared animation clock, per-binding gating, pause layers (`PlaybackPauseLayer`: `routeMoving`, `fastScroll`, `lowPower`, `surfaceHidden`, `appInactive`, `reducedMotion`, `overlayShown`), fps caps derived from the spec size; `follow` lends the frames to a follower that is not a binding (`PlaybackSubscription.cancel`). `PlaybackPolicy.standardPausingLayers` is every layer but `reducedMotion` |
| `PlaybackActivity` / `PlaybackActivityPolicy` | The one host-facing pause seam: follows a `PlaybackLifecycleSource`, a `lowPower` and a `reducedMotion` `ValueListenable<bool>`, and holds from `holdOverlay()`, and sets the five layers it owns on the clock. Zero grace by default; `dispose` clears what it set |
| `PlaybackLifecycleSource` (seam) | The app's `AppLifecycleState` (or `null`: unknown); `WidgetsPlaybackLifecycleSource` in an app, `ManualPlaybackLifecycleSource` in tests |
| `PlaybackTickSource` (seam) | The clock's per-frame callback; `SchedulerPlaybackTickSource` in an app, `ManualPlaybackTickSource` in tests |
| `GlyphSpriteSource` (seam) | The one narrow seam to baked glyphs: `spriteOf`, `holdPageOf`, page listeners. `GlyphAtlas` implements it |
| `AtlasSprite` | Page image + source rectangle; the sprite capability of an `AssetPaintable` |

Behaviour that matters to a surface:

- **Staged readiness, no visible failure.** A binding paints the best stage
  its entry has reached, the scope's placeholder before any. An attempt that
  fails (offline, server error, bad data) leaves the stage where it was, so a
  cell keeps its placeholder until detached. Nothing is signalled; the error
  is `lastError`, for logs. The attempt is repeated on the next attach, on
  `connectivityRestored()` (for failures the producer called transient, and
  only for entries still attached) and on `retry()`. Cancellation is not a
  failure.
- **Pinning and the budget.** An entry with a live binding is never evicted.
  Unattached entries that reached a first frame or better stay until the byte
  budget of their tier needs the room (least recently used first), or until
  `clearAll()` / the memory-pressure signal; one that produced nothing beyond
  a placeholder is dropped at the last detach, and a running attempt is
  cancelled then. Eviction can never invalidate a binding: a binding gives
  back exactly what it took, once, and never looks its entry up again.
- **One attempt per entry**, however many surfaces attach.
- **Playback.** A binding is advanced by the shared clock when its profile
  animates, it is `visible`, its paintable `isAnimated` and no pause layer is
  set. The clock asks the engine for frames only while something plays.
  Paintables never schedule timers; they derive their frame from the context
  time. A pause freezes and a resume continues (never a rewind, never a jump
  to the live position): `now` stands still while paused and jumps once on the
  first frame after, and a paintable must go on from where it stopped, as the
  frame-sequence one does.
- **Pause policies.** `PlaybackActivity` maps the app's lifecycle onto the
  clock: `inactive` (focus lost) sets `appInactive`; `hidden`, `paused`,
  `detached` set it and `surfaceHidden`; an unknown state sets nothing. The
  host feeds `lowPower` (the SDK reports no battery state and the package takes
  no battery plugin) and `reducedMotion` (which does not stop playback unless
  the policy adds the layer), and holds `overlayShown` per overlay.
  [ADR 022](../../docs/adr/022-asset-cache-and-media-pipeline.md) lists what the
  reference desktop client does that is not replicated.
- **Threading.** Single-threaded on the UI isolate: calls, producer reports,
  listeners and painting. Decoding may happen elsewhere; its results are
  reported here from the UI isolate.

### The glyph media form

A unicode key bound in a scope that has a glyph source registered
(`scope.glyphSource = atlas`) is the glyph form: a baked sprite on an atlas
page, never a paragraph at scroll time on a platform that bakes. It is
placeholder-stage (a circle) with no time limit until its glyph is baked, then
final at `full` with a sprite. The strategy follows the source while the
binding lives: registering one moves bindings made without it onto it, removing
it sends them back to the producer (text). The binding **holds the page its glyph is on**
from attach to detach (a count, never pixels) and has no cache entry, so the
budget cannot evict it and nothing the cache does can change a hold. The pages
belong to the source (the atlas's `GlyphPageResidency`): shared by the
bindings that hold them and by the atlas itself, kept for the retention after
the last hold and released under memory pressure unless held. Registering a new
source moves live bindings to it in place. Without a registered source a
unicode key is an ordinary entry, which is how a platform that draws glyphs as
text plugs a producer that does (`TextGlyphProducer`, below).

### Defaults and how they were chosen

Measured by `test/benchmark/asset_cache_churn_bench_test.dart` (run
`flutter test test/benchmark`): a scroll trace down a catalogue and back, one
row at a time, counting how many attaches on the way back find their entry
still decoded. Cell sizes are decoded RGBA at 3x density; an animated entry
costs two frame buffers, as the Android client counts a Lottie drawable.

| Workload | 4 MiB | 8 MiB | 12 MiB | 16 MiB | 24 MiB | 32 MiB |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Stickers, 192 px (144 KiB), 24 visible, down 4 screens and back | 4% | 33% | 63% | 92% | 100% | 100% |
| Stickers, down 8 screens and back | 2% | 17% | 31% | 46% | 75% | 100% |
| Custom emoji, 102 px (40 KiB), 64 visible, down 4 screens and back | 13% | 53% | 91% | 100% | 100% | 100% |
| Custom emoji, down 8 screens and back | 6% | 27% | 45% | 66% | 100% | 100% |
| Animated stickers, 256 px (512 KiB), 12 visible, down 1 screen and back | 0% | 25% | 100% | 100% | 100% | 100% |
| Animated stickers, down 2 screens and back | 0% | 13% | 50% | 75% | 100% | 100% |
| Animated stickers, down 4 screens and back | 0% | 6% | 25% | 38% | 75% | 100% |

- **`AssetCacheBudgets.defaults`: 24 MiB of stills, 12 MiB of animations.**
  24 MiB keeps all of the last four screens of stickers and of custom emoji
  (pager keep-alive and scroll-back); 12 MiB of animations keeps the one screen
  just scrolled past. Both are within the Android client's own figures (a 15
  to 30 MB bitmap cache, a 10 MiB animation cache). Pinned bytes come out of
  the budget first.
- **`PlaybackPolicy` fps caps: 30 fps up to 270 px on the longer edge (90 dp at
  density 3, Android's rule for emoji; Desktop repaints no faster than every
  33 ms), 60 fps above.** A cap is a ceiling, not a target: on a 120 Hz display
  an uncapped animation would repaint its surface twice as often for no visible
  gain. The benchmark's playback line shows the cap halving repaint requests
  for small assets (30000 against 60000 over 600 frames and 100 bindings) at
  about 25 us of dispatch per frame in debug mode.
- Churn cost: about 2.5 us (debug mode) per attach, produce, detach and
  eviction cycle on a 5000-entry catalogue through a 24 MiB budget. Absolute
  times are inflated by asserts and are never asserted; the hit-rate tables are
  counts and are exact.

`test/benchmark/asset_cache_ratio_bench_test.dart` reduces the same cache (plus
clock fan-out to many animated bindings, page-hold churn against a real
`GlyphPageResidency` and memory pressure) to ratios, counts and rates that the
nightly job tracks against committed baselines; see
[benchmarks/README.md](../../benchmarks/README.md).

### Host contract

| The host provides | The host must not |
| --- | --- |
| One `AssetCacheScope` per cache it wants shared, created once and disposed when it goes away | Keep a static instance, or create one per surface (entries would not be shared) |
| A `producer` that makes the paintables of non-glyph content (usually an `AssetPipeline`), reporting through `AssetProgress` on the UI isolate | Report from another isolate or thread, or throw for a failed attempt (report `fail`) |
| A `glyphSource` (the atlas) on platforms that bake glyphs, set by the host or by the page that owns the atlas; no source where glyphs are drawn as text | Pass a `GlyphAtlas` to anything but `glyphSource`, or read atlas types through the cache |
| Budgets for its device class (`budgets`) and the memory-pressure signal (`memoryPressure:` or `clearAll()`) | Evict by hand to "free" a bound entry: bound entries are pinned |
| `connectivityRestored()` when the network returns | Make the cache touch the network |
| One `PlaybackActivity` per scope, fed a `WidgetsPlaybackLifecycleSource`, its own `lowPower` detection (and `reducedMotion` where the engine does not report it), and a `holdOverlay()` per dialog, sheet or route over the chat; `routeMoving` and `fastScroll` set directly on the clock | Set `appInactive`, `surfaceHidden`, `lowPower`, `reducedMotion` or `overlayShown` by hand next to an activity (it owns them), run a timer per animation, or call a paintable's `paint` outside a paint |
| A custom `AssetPaintable` that goes on from where it stopped after a pause | Derive its frame from `clock.now` alone: `now` jumps by the whole pause on the first frame after |
| `detach()` for every binding it attached, `visible` set to what it shows | Keep a `paintable` or a `sprite` across frames: a better stage replaces one, a page release can end the other |

Decisions: [ADR 022](../../docs/adr/022-asset-cache-and-media-pipeline.md)
(cache core, staged readiness, producer seam, page residency) and
[ADR 006](../../docs/adr/006-panel-catalog-viewport.md) (the amendment on baked
glyphs). Glossary: [Content and Assets](../../docs/content/CONTEXT.md),
[Panel Catalog](../../docs/panel-catalog/CONTEXT.md) (glyph atlas terms).

## The fetch and decode pipeline

`AssetPipeline` is the `AssetProducer` that makes the entries of a scope by
fetching and decoding. The scope still owns one attempt per entry, stage
bookkeeping, budgets and cancellation when the last binding leaves; the
pipeline adds what a screenful of entries needs on top of it, and nothing for
unicode glyphs, which bind to baked sprites through the glyph source and never
reach it (its queues and caps never delay a glyph, and the baker stays paced by
frames on the root isolate).

```dart
final pipeline = AssetPipeline(
  fetcher: hostFetcher,                    // network, disk tier, file refs
  decoders: DecoderRegistry()
    ..register(MediaForm.still, stillDecoder)
    ..register(MediaForm.vectorAnimation, vectorDecoder),
  resolver: hostResolver,                  // optional: bare keys
);
final scope = AssetCacheScope(producer: pipeline, glyphSource: atlas);
pipeline.know(descriptor);                 // descriptors the host already holds
```

| Type | Role |
| --- | --- |
| `AssetPipeline` / `AssetPipelineLimits` | Resolve, fetch, decode, report stages. Caps: 6 fetches, 2 decodes, 16 fetched items waiting for a decode slot, 4096 remembered descriptors (all configurable) |
| `ContentFetcher` (seam) | `fetch(FetchRequest)`: the thumbnail or the content of a descriptor as bytes or a file, or a `FetchFailure` that is `transient` or `permanent`. Owns network, file-reference refresh and the disk tier |
| `FetchRequest` / `FetchPart` / `FetchedContent` | What is asked (the `AssetPriority` class included, for a fetcher with its own network queue), which bytes, what comes back (`FetchedBytes` or `FetchedFile`) |
| `CancellationToken` | Cancelled when the last binding of the entry leaves; the fetcher stops and settles its future |
| `Decoder` (seam) / `DecoderRegistry` | One decoder per `MediaForm` (still, vector animation, video), registered by the host from adapter packages: `DecodeRequest` plus an `AssetProgress` to stages. The glyph form has none by design |
| `AssetDemand` / `AssetPriority` | What the entry's bindings want, live: `visible` while one shows it, `preload` when all are hidden; a thumbnail is `placeholder` |
| `AssetPipelineError` | Why an entry could not be made when no fetch or decode failed (unknown to the resolver, no decoder); `lastError` only |

Behaviour that matters to a host:

- **Priority.** Waiting work is served `placeholder` (thumbnail) before
  `visible` before `preload`, oldest first within a class, separately for the
  fetch and the decode queue. The class of content work is read live, so an
  entry that scrolls into view jumps the preloads. Running work is never
  preempted.
- **Caps and backpressure.** At most 6 fetches and 2 decodes run; the Android
  client runs 5 small and 2 large file loads. Fetching is held back while 16
  fetched items wait for a decode slot, so a slow decoder cannot pile up
  bytes. These are starting values from the research, not measured on a device.
- **Cancel.** Queued work is dropped, a running fetch gets its token cancelled,
  a running decode its task cancelled, and the slot is free at once. A late
  result is ignored.
- **Dedupe.** One attempt per entry (content key plus spec) however many
  surfaces attach. The same content at two sizes is two entries and two
  fetches; the host fetcher's disk tier is what shares the bytes.
- **Bare keys.** A key with no known descriptor goes to the host
  `ContentResolver`, batched with every other key asked for in the same turn
  and never asked twice while in flight. The entry stays `none` until it
  resolves. Descriptors are remembered in a bounded LRU; `know` seeds it.
- **Failure is never shown.** Offline, a server error, an unknown key, no
  decoder and bad data all end the attempt and leave the entry at its stage.
  The attempt is repeated on re-attach and `retry()` for every failure, and on
  `connectivityRestored()` for transient ones only: a `FetchFailure.transient`,
  any other error a fetcher throws, and a resolver that cannot be reached.
  Permanent: `FetchFailure.permanent`, a key the resolver leaves out, no
  resolver, no decoder, and every decode failure. A failed thumbnail is
  ignored.

### Host contract

| The host provides | The host must not |
| --- | --- |
| A `ContentFetcher` that owns the network, file-reference refresh and the disk tier, reports `FetchFailure.transient` for offline and busy and `permanent` for missing content, and settles a cancelled fetch | Make the pipeline cache bytes or touch the network itself, throw instead of failing the future, or leave a cancelled fetch pending |
| A `DecoderRegistry` with one decoder per `MediaForm` it shows | Register a decoder for `glyph` (unicode glyphs bind through the glyph source) or two for one form |
| A `ContentResolver` if bare keys can occur, and `know(descriptor)` for descriptors it already holds | Expect an unknown key to be an error the user sees: the entry stays at `none` |
| `AssetCacheScope.connectivityRestored()` when the network returns | Treat `lastError` as UI state |
| `dispose()` on the pipeline after the scope | Dispose the fetcher, decoders or resolver through the pipeline: they stay the host's |

Adapter authors run `AssetFetcherContract.run` and `DecoderContract.run` from
`testing.dart` against their implementations; the package tests the pipeline
with `FakeFetcher`, `FakeDecoder` and `ManualClock`.

## Widgets and inline embeds

Two ways to draw cache content outside the catalogue viewport: a widget
(`ContentView`, for a composer field, a header, a sticker in a bubble) and a
painter-based inline embed (`ContentEmbed`, for content set inside text that a
markdown body lays out and paints itself). Both attach `(content, spec,
profile)` to the host's scope and so share its entries, budgets, playback clock
and pause layers; a unicode glyph on a platform that bakes holds the page of
its glyph from attach to detach (the page count is taken at attach, given back
once at detach, whatever the cache does in between).

```dart
AssetCacheProvider(
  scope: hostScope,                       // created and disposed by the host
  child: ContentView(
    content: const ContentKey.document('5368'),
    preset: AssetPresets.keyboardCell(extent: 34, devicePixelRatio: dpr),
    semanticLabel: 'waving hand',
  ),
)
```

| Type | Role |
| --- | --- |
| `AssetCacheProvider` | `InheritedWidget` handing the host's `AssetCacheScope` down; `of` throws without one, `maybeOf` is null. Never disposes the scope |
| `ContentView` | Attaches on first build, again only when content, preset or scope change (new attach first, old one given back after, so a shared entry or glyph page is never left unheld), detaches on dispose. Sized by the preset; repaints on the binding's signal, never rebuilds for it. Follows `TickerMode` for `visible` |
| `AssetPreset` / `AssetPresets` | Size (logical), `AssetSpec` and `AssetProfile` in one value. `keyboardCell(extent:, devicePixelRatio:)`; `inlineMessage(ascent:, descent:, devicePixelRatio:)` (a square of 1.2 times the line height, rounded to device pixels, the Telegram Android rule) and `inlineFontSize(fontSize:, ...)` for text with no font metrics; `emojiOnly(step:, ...)` (one item of an emoji-only message, a font-size step plus a 4 px box) and `emojiSticker(extent:, autoplay:, restFrame:, ...)` (the single-emoji sticker, plays once then rests); `square(extent:, profile:, ...)` for any other explicit extent; hosts build their own |
| `InlineEmbed` (seam) | What a body lays out and paints: `sizeHint`, `paint(canvas, rect, context)`, a `Listenable` invalidation signal, `visible`, `dispose`. No widget, no asset type |
| `PlayableEmbed` (seam) | An `InlineEmbed` that plays and can play again: `playback`, `replay()` (false while a pass runs). `ContentEmbed` is one; a body checks `embed is PlayableEmbed` |
| `InlineEmbedResolver` (seam) | Maps an `InlineEmbedTarget` (scheme, id, alt) and `InlineEmbedMetrics` (font size, ascent, descent, density) to a new `InlineEmbed`, or null |
| `ContentEmbed` | The `InlineEmbed` over an `AssetBinding`: attaches at construction with a preset, paints the paintable at the shared clock's time, detaches in `dispose` |
| `ContentEmbedResolver` | Resolves targets spelled as `ContentKey.encoded` (`unicode:1F44D`, `document:5368`, `external:...`) to `ContentEmbed`s, with `AssetPresets.inlineMessage` over the metrics' ascent and descent unless the host passes `presetFor` |
| `TextGlyphProducer` | Paragraph strategy of the glyph form for a platform with no atlas (the web): unicode keys are final on attach and paint a cached paragraph in the system font; other keys go to the producer it wraps. Compose it as the scope's producer only where no `glyphSource` is registered |

Behaviour that matters to a host:

- **A view or embed signals; it does not poll.** Stages, a landed atlas page
  and animation frames reach it as the binding's signal. A body repaints on an
  embed's signal and calls `dispose` when its text goes away; a parent that
  rebuilds `ContentView` every frame costs no attach.
- **Playback.** An animated preset plays only while the view is shown
  (`TickerMode` enabled, `visible` true for an embed), the clock is not paused
  by a host layer, and the paintable animates. A body sets `visible = false`
  on an embed it scrolled out of view.
- **Atlas.** The view and the embed draw a baked sprite scaled to their box,
  so message-sized content reuses the one atlas size; there is never a second
  atlas. A glyph the atlas does not know stays a circle placeholder (the glyph
  form never falls back to text where an atlas is registered).
- **Inline embeds in message bodies.** The markdown library lays an embed out
  as a placeholder in its paragraph, paints it in a live pass after the glyph
  picture, and keeps the alternative text for copy, selection and
  accessibility; the root `chat_scroll_view` package adapts this package's
  `InlineEmbedResolver` to the library's own contract (`ChatMarkdownBody.embedResolver`).
  A host hands the body one resolver (compose by scheme on its side). A bare
  emoji character in a body stays a glyph; `![alt](scheme:id)` is the embed
  spelling. The composer's `InlineContentSpanBuilder` hook (the span must be as
  long as the alternative text) is wired by the composer's field widget,
  outside this package.
- **Other things that animate with the cache.** `PlaybackClock.follow` lends
  the shared clock to a follower that is not a binding, with the same frame
  cadence and pause layers (the viewport feeds the dust over hidden spoilers
  from it); cancel the `PlaybackSubscription` and the clock sleeps again.

Decisions: [ADR 022](../../docs/adr/022-asset-cache-and-media-pipeline.md)
(paintable, glyph form, bindings) and
[ADR 029](../../docs/adr/029-host-integration.md) (embed seam, the root viewport's dependency on this package) and
[ADR 037](../../docs/adr/037-spoiler-and-mention-inline-styles.md) (the shared clock drives the spoiler fill).

### Host contract

| The host provides | The host must not |
| --- | --- |
| An `AssetCacheProvider` above the widgets that draw content, or a `scope:` argument | Dispose the scope while views or embeds are attached (`attach` after `dispose` throws), or expect the provider to dispose it |
| Presets for its surfaces (`AssetPresets` or its own `AssetPreset`), sized from the text and density the surface really has | Pass a pixel size of its own: the spec is part of the entry identity, so a stray size is a second decode |
| `InlineEmbedResolver`s registered per scheme where it sets up a body, and `dispose` for every embed the body is done with | Keep an embed past its text, or share one embed between two places (each `resolve` returns an embed of its own) |
| `TextGlyphProducer` as the scope's producer on a platform without an atlas | Use it where an atlas is registered (a paragraph at scroll time is what the glyph form avoids), or leave a hidden animated embed with `visible` true (it keeps costing ticks) |

## Glyph atlas (`glyph_atlas.dart`, `testing.dart`)

Bakes the glyphs a host supplies into fixed-size **glyph atlas pages** and
answers where each **baked glyph** (sprite: page plus source rectangle) is.
`AssetCacheScope.glyphSource = atlas` exposes it to the surfaces that bind
through the scope: unicode bindings resolve their `paintable.sprite` from it
and every binding hears a page landing. Surfaces never see the atlas type: they
draw the sprite their binding's paintable exposes. Each unicode
binding **holds the page its glyph is on** from attach to detach; the pages
themselves sit in the atlas's `GlyphPageResidency` (see below), so nothing done
to the cache ever changes a count. The atlas implements `GlyphSpriteSource`,
the only thing the cache knows about it.
Terms: [Panel Catalog glossary](../../docs/panel-catalog/CONTEXT.md)
(Glyph atlas page, Bake, Baked glyph).

| Piece | Role |
| --- | --- |
| `GlyphAtlasLayout` | Page 2048 px, glyph capped at 72 px, 2 px gutter: 676 cells per page; the three constants are the only knobs |
| `GlyphAtlasIndex` | Fixed plan: which page and cell each glyph is baked into (pure data) |
| `GlyphBaker` | Strips of a few glyphs, then one page composed per step; the caller paces the steps |
| `GlyphRasteriser` (seam) | Paints one glyph; `ParagraphGlyphRasteriser` uses the system font |
| `GlyphPageStore` (seam) | Keeps composed pages; the in-memory fake is in `testing.dart` |
| `GlyphBakeScheduler` | Runs one baker step per frame, only while the pause signals allow; resumes after a few quiet frames |
| `BakeGovernor` / `BakePacing` | Glyphs per frame (up to 16) from measured frame cost: halves near the budget, climbs back while cheap |
| `BakePauseSignals` | Three host-owned `ValueListenable<bool>`: panel visible, scrolling, panel opening |
| `BakeFrameSource` (seam) | The frame clock: `SchedulerBakeFrameSource` in an app, `FakeBakeFrameSource` in tests |
| `GlyphAtlas` | A host's whole bake: baker + scheduler + the page images sprites are drawn from; `spriteOf(glyph)` is null until the glyph's page is baked and loaded; `retire()` hands the drawn art to the atlas that replaces it (`predecessor:`) |
| `GlyphPageResidency` | Owns the resident page images: a hold count per page (bindings, and the open panel for every page), a retention time-to-live (default 60 s, `retention:`) once nothing holds a page, release of the pages nothing holds, at once, on `memoryPressure` (a held page, such as any page while the panel is open, is kept) |
| `SystemMemoryPressure` | The platform's memory-pressure signal as a `Listenable` (the production `memoryPressure`) |
| `MemoryGlyphPageStore` | In-memory page store, for an atlas that does not persist |
| `GlyphAtlasPersistence` | `GlyphCacheStore` + `GlyphArtVersionSource` + density: an atlas given this instead of a store restores its pages on the next launch |
| `GlyphCacheStore` (seam) | One committed generation (what the next launch finds) and at most one staged one; `GlyphCacheStore.forPlatform(path)` is a `dart:io` file store, in memory on the web; `FakeGlyphCacheStore` in `testing.dart` |
| `GlyphCacheKey` | Art version + density + glyph size + layout version + catalogue hash; decides hit, stale, discard or miss |
| `GlyphArtVersionSource` (seam) | Says whether the system emoji art changed; `FixedGlyphArtVersion`, `ComputedGlyphArtVersion` (a pixel fingerprint computed once; `GlyphPixelReader` draws the sentinels); `FakeGlyphArtVersionSource` in `testing.dart` |
| `GlyphBakeObserver` (seam) | Shown each glyph's baked cell (RGBA bytes) so a glyph-support probe shares the bake pass; `CallbackGlyphBakeObserver` builds one from three functions (the bridge to a consumer that must not depend on this package); `FakeGlyphBakeObserver` in `testing.dart` |
| `GlyphAtlas.forPlatform` | The platform strategy, taking a `GlyphAtlasRequest` (the arguments of `GlyphAtlas` in one value): an atlas on Android, iOS and desktop, `null` on the web (draw text, start no bake) |

### Disk cache

With a `GlyphAtlasPersistence` the pages outlive the process. A launch reads
the art version, builds the key and compares it with the persisted set:
*hit* restores the pages (one read per frame, waiting only for scrolls and the
open animation), *stale* keeps drawing the old pages while the new set bakes
behind them and swaps once, *discard* and *miss* show circles and bake as on a
first run, persisting each page as it lands. Damaged or missing pages are a
miss for that page. A failing disk is reported once and never stops the bake.
Pages are raw RGBA (16 MiB each, 48 MiB for the current catalogue) with a
length-checked header; the cache directory is the host's (no plugin here) and
may be cleared by the platform at any time. QA steps for the first run, the
cold start and the OS-update case:
[qa-glyph-cache.md](../../docs/panel-catalog/qa-glyph-cache.md).

Host contract:

| The host provides | The host must not |
| --- | --- |
| The glyph list (the data layer decides which glyphs exist) | Ask the baker to detect missing glyphs or fall back to a paragraph |
| Pacing: a `GlyphBakeScheduler` on a `BakeFrameSource` (or its own calls to `step`) | Call `step` from a spawned isolate (text and picture APIs are root-isolate only) |
| The three pause signals, updated from the real viewport and panel | Bake beside a fling or the open animation; a hidden panel bakes nothing |
| `prioritise(glyphs)` with the visible band when scrolling settles | Expect a visible glyph before its whole page is composed; cells never move |
| `dispose()` on the scheduler (and `SchedulerBakeFrameSource`) when the panel is torn down | Dispose the baker first: the scheduler leaves no frame request or listener behind |
| `retire()` on the old atlas, and its `RetiredGlyphArt` given to the new one, when the plan must change | Run two atlases over one `GlyphCacheStore` at once: a cache has a single writer, and the successor waits for the retired atlas's disk work |
| `reportScrolling(reporter:, scrolling:)` from each surface that scrolls | Share one reporter between surfaces, or leave a reporter at `true` when its surface goes away |
| A `GlyphPageStore` | Mutate or share a stored page; handles are cloned on write and read |
| A `GlyphPageResidency` per atlas: `retention` and `memoryPressure: SystemMemoryPressure()` (the host disposes the signal) | Keep a sprite across frames: a page can be released, ask `spriteOf` again; expect memory back from a released page while the store is the in-memory one (it keeps the texture) |

`testing.dart` is opt-in: production entry points never export or import it.
The contract suites are written with `flutter_test`, so the package lists
`flutter_test` under `dependencies` (a library cannot import a dev dependency).
The suites have no consumer outside this package yet; moving them to a package
of their own would give `catalog_assets` a dev dependency on a package that
depends on it, which the workspace dependency lint rejects as a cycle.

`testing.dart` ships `ManualRetentionTimers` and `ManualMemoryPressure` (the retention
and the pressure a test moves by hand), `FakeGlyphRasteriser` (predictable pixels, no emoji font;
`onPaint` to model a slow or failing glyph), `FakeGlyphPageStore`,
`FakeBakeFrameSource` and `ManualBakeClock` (frames and time a test steps),
`ImagePixels`, `SampleGlyphCatalogue` (a catalogue of the current size without any emoji
data), and the contract suites `GlyphRasteriserContract.run`,
`GlyphPageStoreContract.run` and `BakeFrameSourceContract.run` for adapter authors.
For the pipeline: `FakeFetcher` (serves fixed content, goes offline, answers by itself or waits for the test), `FakeDecoder`, `ManualClock` (latency without waiting) and the contract suites `AssetFetcherContract.run` and `DecoderContract.run`.
For the cache core: `FakeAssetProducer` (every attempt waits for the test, which
plays the producer through `FakeAssetAttempt`), `FakeAssetPaintable` (given
`frameDurations` it plays a sequence, holds its rest frame and restarts),
`FakeGlyphSpriteSource` (pages baked and released by hand, hold counts
readable), `ManualPlaybackTickSource`, `ManualPlaybackLifecycleSource`, and the contract suites
`GlyphSpriteSourceContract.run` (the fake and `GlyphAtlas` both pass it),
`PlaybackTickSourceContract.run` (the manual and the scheduler source both pass
it), `PlaybackLifecycleSourceContract.run` (the manual and the widgets source
both pass it; it moves the process-wide lifecycle, so pass `tearDownHarness`
to restore it) and `AssetPlaybackContract.run` (one pass, the rest frame, restart; the
fake and `PlayingImagePaintable` both pass it).
For the widget and embed seams: `FakeInlineEmbed`, `FakePlayableEmbed`,
`FakeInlineEmbedResolver` and the contract suites `InlineEmbedContract.run`
(`ContentEmbed` and the fakes both pass it), `PlayableEmbedContract.run` (the
same) and `InlineEmbedResolverContract.run`.
On-device checks: `example/integration_test/glyph_atlas_bake_test.dart` (bake
and visual check) and `glyph_atlas_paced_bake_test.dart` (paced bake idle, while
the panel opens, during a fling).
