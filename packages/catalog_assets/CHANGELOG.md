# Changelog

All notable changes to `catalog_assets` are documented in this file. The format
is loosely based on [Keep a Changelog](https://keepachangelog.com/); this package
is pre-1.0.

## [Unreleased]

### Added (pause policies of the reference desktop client)

- `PlaybackActivity` and `PlaybackActivityPolicy`: the one seam that turns the
  app's lifecycle (`PlaybackLifecycleSource`, `WidgetsPlaybackLifecycleSource`
  in an app), a host-fed `lowPower` and `reducedMotion` and `holdOverlay()`
  holds into the clock's pause layers. Focus lost (`inactive`) sets
  `appInactive`; `hidden`, `paused` and `detached` also set `surfaceHidden`;
  an unknown state, or a first `detached`, sets nothing. Grace periods default
  to zero, as the reference client's pause is immediate. `dispose` clears only
  the five layers it owns and disposes none of its inputs.
- `PlaybackPauseLayer.appInactive`, `reducedMotion` and `overlayShown`.
- `PlaybackPolicy.standardPausingLayers`.
- Testing: `ManualPlaybackLifecycleSource` and
  `PlaybackLifecycleSourceContract` (run against the manual and the widgets
  source).

### Changed (pause policies)

- **Breaking (source)**: `PlaybackPauseLayer` has three more values, so an
  exhaustive `switch` over it stops compiling until it handles them.
- **Behaviour**: `PlaybackPolicy.pausingLayers` defaults to
  `standardPausingLayers`, every layer but `reducedMotion`, where it was
  `{...PlaybackPauseLayer.values}`. A clock whose host sets `appInactive` or
  `overlayShown` pauses on them; `reducedMotion` alone does not stop playback.
  A host that passed the old default explicitly gets `reducedMotion` too, and
  one that wants it adds it.
- **Docs**: `PlaybackClock.now` stands still while paused and jumps once on
  the first frame after; the old text said it kept counting. Resuming where
  the animation stopped is the paintable's job (the frame-sequence one does).

### Added (one pass, a rest frame and a replay)

- `AssetProfile.loop` is honoured and gains `restFrame` (`AssetRestFrame`):
  a profile that does not loop plays one pass and holds the first or the last
  frame. `AssetBinding.playback` (`AssetPlayback`: idle, playing, ended) says
  where it stands, signalled on the binding's listeners, and an ended binding
  costs no ticks. `AssetBinding.replay()` plays another pass and returns false
  while one runs or loops (a pass is never rewound), when hidden or detached,
  and for an entry with no animation yet.
- `AssetPaintable.isHolding` and `restart()`, and `loop` / `restFrame` on
  `AssetPaintContext`. Source-breaking for an implementer of `AssetPaintable`
  or `AssetBinding`: a still returns false from both.
- `PlayableEmbed` (`ContentEmbed` implements it): `playback` and `replay()` for
  a body that replays an embed without reaching the binding.
- `AssetPresets.emojiSticker(restFrame:)`.
- Testing: `FakeAssetPaintable(frameDurations:)` plays a sequence;
  `AssetPlaybackContract` (run against the fake and `PlayingImagePaintable`),
  `FakePlayableEmbed` and `PlayableEmbedContract`.

### Added (embed metrics and explicit-extent presets)

- `InlineEmbedMetrics.ascent` and `descent`: the line's vertical metrics in
  logical pixels, so an embed is sized from the line it sits in.
- `AssetPresets.square` (any explicit extent and profile), `emojiOnly` (one
  item of an emoji-only message, from a font-size step) and `emojiSticker`
  (the single-emoji sticker; plays once, `autoplay` decided by the host).

### Changed (embed metrics)

- Source-breaking: `InlineEmbedMetrics` requires `ascent` and `descent`, and
  `AssetPresets.inlineMessage` takes `ascent:` and `descent:` instead of
  `fontSize:`. Its extent is now `1.2 * (ascent + descent)` rounded to whole
  device pixels (Telegram Android's rule), so every embed of a paragraph
  shares one spec per key. `extentPerFontSize` is gone. The old font-size form
  remains for text with no metrics as `AssetPresets.inlineFontSize`.
  `ContentEmbedResolver` and `FakeInlineEmbedResolver` size embeds with the new
  rule.
### Changed

- Source-breaking: the contract suites in `testing.dart` are statics on a type
  per seam: `runGlyphCacheStoreContract(...)` is now
  `GlyphCacheStoreContract.run(...)`, and likewise `GlyphPageStoreContract`,
  `GlyphRasteriserContract`, `BakeFrameSourceContract`,
  `GlyphSpriteSourceContract`, `PlaybackTickSourceContract`,
  `AssetFetcherContract`, `DecoderContract`, `InlineEmbedContract` and
  `InlineEmbedResolverContract`.
- Source-breaking: `sampleGlyphCatalogue({count})` is
  `SampleGlyphCatalogue.glyphs({count})` and `sampleCatalogueSize` is
  `SampleGlyphCatalogue.size`.
- Source-breaking: the platform forks are statics on the types they build.
  `createGlyphCacheStoreForPlatform(path)` is `GlyphCacheStore.forPlatform(path)`
  and `createGlyphAtlasForPlatform(request)` is `GlyphAtlas.forPlatform(request)`;
  the free functions and their `platform/` exports are gone. The forks live in
  `src/atlas/environment_specific/` (a hub plus `_vm` / `_js` files, each
  defining a `$entry`), and the `dart:io` stores there are
  `GlyphCacheStore$File$VM` and `GlyphPageStore$File$VM` (not exported).

### Fixed

- `AssetCacheScope(systemFonts:)`: glyphs drawn as text lay out again and
  repaint when the engine's fonts change (`PaintingBinding.systemFonts`). A
  browser fetches the font that draws an emoji only once it meets one, so a
  glyph laid out before it arrived kept drawing the missing-glyph box.
- `TextGlyphProducer(fontsReady:)`: glyphs drawn as text wait, as the
  scope's placeholder, until the fonts that draw them are there, so a grid
  shows placeholders, not missing-glyph boxes, while a browser downloads the
  emoji font.

- A binding whose profile does not animate paints at the playback time of its
  first paint, so an animated paintable shows one frame there. It painted at
  the clock's live time, which runs for the scope's other animations, so it
  stepped in bursts whenever its surface repainted. It also passes
  `AssetPaintContext.animate`, new and true by default, as false: a paintable
  that keeps its own playback, shared by every surface of its entry, does not
  step for such a paint. Sharing an entry with a playing surface, a still one
  shows the frame that surface is at; `AssetVariant.firstFrame` holds one.

- `ParagraphGlyphRasteriser` draws nothing for a sequence the font cannot
  form into one glyph (its layout wraps onto a second line). A joined emoji a
  font lacks, such as 👁️‍🗨️ on some Android fonts, used to be drawn as its
  parts wrapped and cut by the cell (half an eye over half a speech bubble);
  an empty cell is what a glyph-support probe reads as a glyph the system
  cannot draw, so the emoji is now hidden.
- `LayeredGlyphSource` gives each layer a block of page indices of its own
  (`layerPageStride`), so a surface that batches by page index no longer cuts
  a later layer's glyph from the first layer's page: a tone chosen for the
  first time showed the first emoji of the catalogue.

### Added

- `GlyphSpriteSource.waitsForSprite(glyph)` (source-breaking for
  implementers): whether a sprite for the glyph is on its way. `GlyphAtlas`
  answers yes for every planned glyph; `FakeGlyphSpriteSource` takes
  `onDemand` and `learn()`, and the contract suite covers it.
- `LayeredGlyphSource`: one glyph sprite source over a background-baked first
  layer and layers added on demand ([ADR 022](../../docs/adr/022-asset-cache-and-media-pipeline.md)
  amendment).

### Changed

- A glyph binding whose source has no sprite and does not wait for one paints
  the glyph as text (`firstFrame`) instead of keeping the circle, and moves to
  the sprite when its page arrives.

### Added

- `TextGlyphProducer.defaultFontScale` (0.85): the one number for a glyph's font
  size within its box, used by the paragraph strategy, the baked one
  (`ParagraphGlyphRasteriser`) and the variant picker, so they cannot drift.
- `test/benchmark/asset_cache_ratio_bench_test.dart`: churn, LRU pressure,
  clock fan-out and page-hold ratios for the nightly job
  (`benchmarks/README.md`). Nothing a consumer sees.

### Changed

- Change notification is `package:listen` (`listen: ^1.0.1`) instead of
  `content_model`'s removed `Observable`: `AssetBinding` and `InlineEmbed` are
  `Listenable`s. A listener added twice is called twice, `addListener` on a
  detached binding or a disposed embed asserts in debug builds (bindings stop
  signalling at detach, `FakeInlineEmbed.invalidate` after `dispose` does
  nothing), and `CancellationToken` reports a throwing callback to
  `Listenable.onError`, which the host sets (this package never does).
  `runInlineEmbedContract` no longer adds a listener after dispose.
- A unicode binding follows `AssetCacheScope.glyphSource` for as long as it is
  attached, not only when it attaches: a source registered after glyphs drew as
  text moves them onto it (a circle until baked, never a paragraph kept for
  good), and a source removed sends them back to the producer instead of
  leaving a placeholder. A disposed scope ignores a source set late (it no
  longer registers a listener).
- `TextGlyphProducer`'s paragraph is laid out once per size, not once per
  position: a rectangle's width is `right - left`, so the same size at two cells
  differs in the last bits and an exact comparison laid the paragraph out again
  at every cell it was drawn in. It also clips only a sequence wider than the
  box instead of every glyph, which cost a save and a clip per cell.

### Removed

- The temporary `legacy_shim.dart` (the readiness-flag cache API) and its
  tests: `panel_catalog` binds through `AssetCacheScope` and `chat_chrome`
  composes a scope with the atlas as glyph source.

### Added (glyph probe bridge)

- `CallbackGlyphBakeObserver`: a `GlyphBakeObserver` made of three functions, so
  the glyph-support probe in `emoji_data` is plugged into the bake pass without
  either package depending on the other.

### Changed (breaking)

- **The readiness-flag cache is replaced by the asset cache core.**
  `CatalogAssetCache`, `CatalogAssetKey`, `CatalogAssetBinding`,
  `CatalogAssetReadiness`, `CatalogAssetCacheType`, `MemoryCatalogAssetCache`
  and `FakeCatalogAssetCache` are no longer exported from
  `catalog_assets.dart`. Code that attached `(key, cacheType)` and read
  `loading` / `ready` / `failed` now attaches `(ContentKey, AssetSpec,
  AssetProfile)` to an `AssetCacheScope` and reads a staged `AssetReadiness`
  (`none`, `placeholder`, `firstFrame`, `full`, with `isFinal`); there is no
  failed stage, and the entry that used to stay `failed` now keeps its
  placeholder and is attempted again on re-attach, on
  `connectivityRestored()` or on `retry()`. `CatalogAssetBinding.sprite`
  becomes `AssetBinding.paintable.sprite` (the sprite capability of an
  `AssetPaintable`). Entries with live bindings are pinned and unattached
  ones are kept in a byte-budgeted LRU (`AssetCacheBudgets`, 24 MiB of stills
  and 12 MiB of animations by default) instead of forever; `evict` and `clear`
  are `clearAll()`, which leaves bound entries alone.
- **`catalog_assets.dart` no longer exports `GlyphAtlas`.** Import
  `glyph_atlas.dart` for it; the cache reaches an atlas only through
  `GlyphSpriteSource`, which `GlyphAtlas` implements and the host registers as
  `AssetCacheScope.glyphSource`. Swapping the source moves live bindings in
  place.
- `catalog_assets` depends on `content_model` (`ContentKey`).
  The `emoji_data` dev dependency is gone: the tests that read the real
  catalogue use `sampleGlyphCatalogue()` (1610 distinct glyphs, the size the
  3 page / 48 MiB budget was measured at; 2704 is the 64 MiB ceiling).
- `GlyphPageHold` implements `SpritePageHold`; `GlyphAtlas` implements
  `GlyphSpriteSource`. No behaviour change.

### Added (asset cache core)

- `AssetCacheScope`, `AssetBinding`, `AssetSpec` (`AssetDecodeMode`,
  `AssetVariant`), `AssetProfile`, `AssetPaintable` (+ `AssetPaintContext`),
  `AssetStage` / `AssetReadiness`, `AssetCacheBudgets` / `AssetTier`, the
  `AssetProducer` seam (`AssetRequest`, `AssetProgress`, `AssetTask`,
  `AssetFailureKind`), `PlaybackClock` / `PlaybackPolicy` /
  `PlaybackPauseLayer` and the `PlaybackTickSource` seam, `GlyphSpriteSource`
  / `SpritePageHold`.
- `testing.dart`: `FakeAssetProducer`, `FakeAssetPaintable`,
  `FakeGlyphSpriteSource`, `ManualPlaybackTickSource`, `sampleGlyphCatalogue`,
  `runGlyphSpriteSourceContract`, `runPlaybackTickSourceContract`.

### Added (content view and inline embed)

- `ContentView`, a widget that attaches `(content, preset)` to the host's scope,
  paints the binding and detaches when it leaves the tree. It keeps one attach
  across rebuilds, takes (and gives back) the atlas page hold of a glyph with
  its attach, follows `TickerMode` for `visible` and gets a repaint boundary
  when its preset animates.
- `AssetCacheProvider`, the `InheritedWidget` that hands the host-created
  `AssetCacheScope` to the widgets below (never disposes it).
- `AssetPreset` and `AssetPresets` (`keyboardCell`, `inlineMessage`): named
  recipes of size, `AssetSpec` and `AssetProfile`.
- `InlineEmbed`, `InlineEmbedResolver`, `InlineEmbedTarget`,
  `InlineEmbedMetrics` and `InlineEmbedPaintContext`: the package-local,
  painter-based embed contract a markdown body can lay out and paint, with
  `ContentEmbed` (over an `AssetBinding`) and `ContentEmbedResolver`
  (`unicode:` / `document:` / `external:` targets).
- `TextGlyphProducer`: the paragraph strategy for a platform without an atlas
  (the web): unicode keys are final on attach and paint as a cached paragraph,
  bounded by the still budget.
- `testing.dart`: `FakeInlineEmbed`, `FakeInlineEmbedResolver`,
  `runInlineEmbedContract` and `runInlineEmbedResolverContract`.

### Added (fetcher, decoders, orchestration)

- `AssetPipeline`, the `AssetProducer` that resolves, fetches and decodes:
  priority classes (`AssetPriority`: placeholder, visible, preload), caps on
  concurrent fetches and decodes with backpressure
  (`AssetPipelineLimits`), cancellation when the last binding leaves, and
  batched `ContentResolver` lookups for bare keys (`know` seeds known
  descriptors).
- Seams `ContentFetcher` (`FetchRequest`, `FetchPart`, `FetchedContent`,
  `FetchFailure`, `CancellationToken`) and `Decoder` (`DecodeRequest`) with a
  `DecoderRegistry` per `MediaForm`.
- `testing.dart`: `FakeFetcher`, `FakeDecoder`, `ManualClock`,
  `runAssetFetcherContract`, `runDecoderContract`.
- **Changed:** `AssetProducer.produce` takes a third argument, an
  `AssetDemand` that says whether a surface shows the entry. `FakeAssetAttempt`
  exposes it as `demand`.

### Added

- **Bake pass shared with the glyph-support probe.** `GlyphBakeObserver` (a
  pure-bytes seam) is shown each wanted glyph's cell, and the reference
  glyphs once, as the baker draws them: `GlyphBaker(observer:)`,
  `GlyphAtlas(observer:)`, `GlyphAtlasRequest.observer`. Readback
  runs after the strip is made, a strip at a time, and not at all for strips
  nobody wants; `GlyphBaker.observationsSettled()` waits for it. Art version
  from pixels: `GlyphPixelReader` (a glyph drawn by a `GlyphRasteriser`, read
  back) and `ComputedGlyphArtVersion` (any computation as a
  `GlyphArtVersionSource`, run once). `FakeGlyphBakeObserver` in
  `testing.dart`.

- **Disk cache for baked pages.** `GlyphAtlasPersistence` (a `GlyphCacheStore`,
  a `GlyphArtVersionSource` and the density) makes a `GlyphAtlas` persist its
  pages: the next launch restores them one page per frame instead of baking
  (`GlyphCacheVerdict.hit`); an art or catalogue change keeps the old pages
  drawing while the new set bakes behind them and swaps in one step
  (`stale`); a density, glyph size or `GlyphAtlasLayout.version` change
  discards them (`discard`); damaged or missing pages are a miss, baked again.
  `GlyphCacheKey`, `GlyphCacheRecord`, `GlyphCacheStore` (committed and staged
  generations), `MemoryGlyphCacheStore`, `createGlyphCacheStoreForPlatform`
  (a `dart:io` file store, in memory on the web), `FixedGlyphArtVersion`,
  `GlyphAtlas.cacheReport` (verdict and how long circles lasted). Fakes and
  contract suites in `testing.dart`: `FakeGlyphCacheStore`,
  `FakeGlyphArtVersionSource`, `runGlyphCacheStoreContract`.
  `GlyphAtlas` and `GlyphAtlasRequest` take `persistence:` instead of
  `store:` (exactly one); `store:` is now optional.

- **Baked sprites for surfaces.** `GlyphAtlas` (baker, scheduler and resident
  page images behind `spriteOf`), `AtlasSprite`, `MemoryGlyphPageStore`, and
  `createGlyphAtlasForPlatform` (an atlas on baking platforms, `null` on the
  web; it takes a `GlyphAtlasRequest`). `CatalogAssetBinding.sprite` is the optional sprite capability;
  `CatalogAssetCache.glyphAtlas` exposes the atlas to the surface;
  `MemoryCatalogAssetCache(glyphAtlas:)` resolves unicode sprites from it,
  notifies binding listeners when a page lands, and has a `dispose()`.
  Implementers of `CatalogAssetCache` / `CatalogAssetBinding` must add the new
  members (return `null` for no atlas / no sprite).

- **Glyph atlas** (`glyph_atlas.dart`) — `GlyphAtlasLayout` (2048 px pages, glyph
  capped at 72 px, 2 px gutter), `GlyphAtlasIndex` / `GlyphSprite`, the paced
  `GlyphBaker`, and the `GlyphRasteriser` / `GlyphPageStore` seams with
  `ParagraphGlyphRasteriser`. Independent of the asset cache.
- **`testing.dart`** — `FakeGlyphRasteriser`, `FakeGlyphPageStore`,
  `ImagePixels` and the `runGlyphRasteriserContract` /
  `runGlyphPageStoreContract` suites.

- **Paced baking** — `GlyphBakeScheduler` drives the baker one step per frame
  from an injected `BakeFrameSource` and clock; `BakeGovernor` adapts glyphs
  per frame (up to 16) to measured frame cost; `BakePauseSignals` pause it for
  a hidden panel, scrolling and the open animation. `GlyphBaker.prioritise`
  bakes the pages holding the visible glyphs first. Fakes and
  `runBakeFrameSourceContract` ship in `testing.dart`.

- **Page ownership and residency.** `GlyphPageResidency` owns the resident atlas
  pages: a hold count per page, a retention time-to-live (default 60 s, set
  with `retention`) layered on keep-until-pressure, and release of the pages
  nothing holds on memory pressure (`SystemMemoryPressure`); a held page, such
  as any page while the panel is open, stays. `GlyphAtlas(residency:)`,
  `GlyphAtlas.residency`, `GlyphAtlas.holdPageOf`; the atlas holds all pages
  while its panel is visible. Unicode bindings of `MemoryCatalogAssetCache`
  hold their glyph's page from attach to detach. `GlyphAtlasRequest`
  takes an optional `residency`. `testing.dart` adds `ManualRetentionTimers` and
  `ManualMemoryPressure`.

- **`GlyphAtlasRequest`** — the arguments of a `GlyphAtlas` in one value.
  `createGlyphAtlasForPlatform` takes it whole instead of repeating eleven
  parameters in each platform file.
- **Replacing an atlas without a gap.** `GlyphAtlas.retire()` stops an atlas
  and returns its drawn art as `RetiredGlyphArt`; `GlyphAtlas(predecessor:)`
  (and `GlyphAtlasRequest.predecessor`) draws that art from its
  first frame, bakes behind it and swaps once, as for a stale persisted set.
  `RetiredGlyphArt.settled` completes when the retired atlas has no disk
  operation in flight; a persistent successor waits for it before it stages,
  so a cache store has one writer. `GlyphAtlas.residentBytes` counts the
  resident pages and the stale set; `GlyphPageResidency` gains
  `addPressureListener` and `takeImage`; `GlyphAtlasPersistence` gains
  `withDevicePixelRatio`.

### Fixed

- **`FileGlyphPageStore.write`** uses a temp file per write, so two overlapping
  writes of one page cannot truncate or interleave each other before the
  rename, and removes its temp file when a write fails.
- **`GlyphBakeScheduler`** drops an unobserved step cost when baking pauses, so
  the first frame after a pause does not slow the pace for a step that ended
  before it.
- A page the store cannot hand back is baked again once instead of staying a
  circle for the life of the process; a second failed read gives up on it.
- Released pages are read back one per frame, and not during a scroll or the
  open animation, when the panel opens or a surface asks for a sprite. Before,
  opening the panel read every released page at once.
- `GlyphAtlas.spriteOf` allocates nothing once a sprite is cut.
- The stale set is released on memory pressure, even while the panel is open,
  and counted in `GlyphAtlas.residentBytes`.
- A stale set is swapped out even when one page of the new plan was given up on
  after two failed reads; before, the old art and the memory of both sets
  stayed for the rest of the process. The given-up page's glyphs show their
  placeholder.
- A composed page clone no longer outlives its page when the page is already
  loading or was given up on.
- `FileGlyphPageStore` and `FileGlyphCacheStore` report an unreadable page,
  manifest or undecodable page through `FlutterError.reportError` with its
  stack. A file that does not exist is still a quiet miss.
- `MemoryCatalogAssetCache`: a binding detaching after `evict` / `clear` no
  longer decrements the attach count of a newer entry with the same key (it
  made a live surface look unretained and could drop its loading entry). A
  binding now releases the entry it attached to.

### Changed

- `GlyphAtlas.reportScrolling` takes a `reporter`: motion is the union of what
  the surfaces sharing an atlas report, so one that settles no longer resumes
  baking under another that is still moving.
- `GlyphBaker.bakeAll` and `GlyphBaker.spriteOf` are test conveniences now
  (`GlyphBakerTesting` in `testing.dart`); a host paces the baker with
  `GlyphBakeScheduler` and draws through `GlyphAtlas`.
- `GlyphAtlas.spriteOf` reads a baked page that was released back from the
  store (a side effect of asking, listeners hear the page when it is drawable
  again), and page listeners are also told when a page is released. A sprite
  is valid only until its page is released; ask again to draw.

- `GlyphBaker` no longer bakes strictly in page order once `prioritise` is
  called; without it the order is unchanged. A page in progress that holds none
  of the prioritised glyphs is dropped and bakes again later.
- The package now depends on the Flutter SDK (`dart:ui` for the baker) and on
  `flutter_test` (contract suites); its tests run with `flutter test`.

### Changed

- **Ready/failed retention** — after the last [CatalogAssetBinding.detach],
  settled entries stay in [MemoryCatalogAssetCache] so re-attach keeps
  readiness (pager keep-alive leave/return). Loading-only orphans are still
  dropped. [CatalogAssetCache.readinessOf] is on the interface;
  [MemoryCatalogAssetCache.evict] / [clear] for explicit drop.

## [0.1.0] - 2026-08-25

### Added

- **`CatalogAssetCache`** — process-wide attach/refcount contract for catalog and
  conversation leaves (key + cache-type / size class + readiness).
- **`CatalogAssetKey`** — sealed unicode / document identity for cache lookup.
- **`CatalogAssetCacheType`** — size-class attach hint (e.g. keyboard vs inline).
- **`CatalogAssetReadiness`** — `loading` / `ready` / `failed` observation.
- **`CatalogAssetBinding`** — surface bind handle with readiness listener.
- **`MemoryCatalogAssetCache`** — in-memory implementation for hosts and tests.
- **`FakeCatalogAssetCache`** — deterministic readiness for widget tests.
- **Unit tests** at the public cache API.

### Non-goals

- No RenderObject dependency; fetch/decode orchestration stays in hosts.
