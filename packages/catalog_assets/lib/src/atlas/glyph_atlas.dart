import 'dart:async';
import 'dart:ui';

import 'package:catalog_assets/src/atlas/atlas_sprite.dart';
import 'package:catalog_assets/src/atlas/bake_frame_source.dart';
import 'package:catalog_assets/src/atlas/bake_governor.dart';
import 'package:catalog_assets/src/atlas/bake_pause_signals.dart';
import 'package:catalog_assets/src/atlas/cache/glyph_atlas_persistence.dart';
import 'package:catalog_assets/src/atlas/cache/glyph_cache_key.dart';
import 'package:catalog_assets/src/atlas/cache/glyph_cache_store.dart';
import 'package:catalog_assets/src/atlas/glyph_atlas_index.dart';
import 'package:catalog_assets/src/atlas/glyph_atlas_layout.dart';
import 'package:catalog_assets/src/atlas/glyph_bake_observer.dart';
import 'package:catalog_assets/src/atlas/glyph_bake_scheduler.dart';
import 'package:catalog_assets/src/atlas/glyph_baker.dart';
import 'package:catalog_assets/src/atlas/glyph_page_residency.dart';
import 'package:catalog_assets/src/atlas/glyph_page_store.dart';
import 'package:catalog_assets/src/atlas/glyph_rasteriser.dart';
import 'package:catalog_assets/src/atlas/memory_glyph_page_store.dart';
import 'package:catalog_assets/src/atlas/report_glyph_atlas_error.dart';
import 'package:catalog_assets/src/glyph/glyph_sprite_source.dart';
import 'package:flutter/foundation.dart';

/// The baked glyphs of one catalogue, in the form a surface draws them: a
/// bake running in the background and, for every glyph whose page is done, an
/// [AtlasSprite].
///
/// It puts the pieces of the bake together for a host: a [GlyphBaker] over the
/// planned [index], a [GlyphBakeScheduler] pacing it on the host's frames, and
/// the page images that are drawn from, read back from the [GlyphPageStore]
/// the moment a page is composed. Page listeners (typically a repaint) hear
/// of a page only when its sprites can be drawn.
///
/// ## Who tells it to wait
///
/// Baking runs only while the panel is visible, nothing scrolls and the
/// panel is not opening ([BakePauseSignals]). The host owns the first and the
/// last as [panelVisible] and [panelOpening]; each surface that scrolls
/// reports the middle one through [reportScrolling] (motion lasts until every
/// surface that reported it has said it stopped) and says what is on screen
/// through [prioritise], because only it knows.
///
/// ## Sharing the pass
///
/// An optional [GlyphBakeObserver] is shown each glyph's cell as the bake
/// draws it, so the glyph-support probe needs no rasterising pass of its own.
/// It sees only what is baked: pages restored from a persisted set are not
/// drawn again, so an observer that must have a verdict for every glyph keeps
/// its own persisted result (valid for one art version) and `wants` nothing the
/// result already holds.
///
/// ## Persistence
///
/// Given a [GlyphAtlasPersistence] instead of a plain store, the atlas keeps
/// its pages across launches. At [start] it learns the system art version,
/// builds the [GlyphCacheKey] and compares it with the persisted set:
///
/// - **hit**: the pages are read back, one per frame, and nothing is baked;
///   a page that is missing, damaged or fails to read is simply baked again;
/// - **stale** (art or catalogue changed): the old pages are read back and
///   keep drawing for the glyphs they hold, while the new set bakes into a
///   staged generation that nothing reads; when its last page is ready the
///   atlas commits it and swaps every sprite in one step. Both sets are
///   resident for that time (about twice the usual memory), which is the
///   price of no visible gap and is paid only after an OS, font or catalogue
///   change. The old images are outside the [residency] (they live for one
///   rebake and are dropped at the swap) but are counted in [residentBytes]
///   and released under memory pressure (they are drawn, not held, so pressure
///   takes them even while the panel is open); the new pages are resident as
///   usual. If a new page is given up on, the swap goes ahead without it;
/// - **discard** (density, glyph size or layout changed) and **miss** (first
///   run, or nothing readable): circles, as without a cache, and every baked
///   page is persisted as it lands.
///
/// Disk work is paced like the bake: one page read per frame, one page
/// written per bake step, and reading waits for a scroll or the open animation
/// to end (it does not wait for the panel to be visible, so a hidden panel is
/// filled in before it opens). A disk that fails is reported once and never
/// stops the bake: the pages stay in memory and the persisted set is left as
/// it was.
///
/// ## Lifetime
///
/// The page images are owned by the atlas's [residency], not held here: it
/// counts the holds on each page (one per leaf binding, via [holdPageOf], and
/// one for the whole panel while [panelVisible] is true), keeps the pages for
/// its retention after the last hold goes, and releases the pages nothing holds
/// at once under memory pressure. A released page is read back from the store, one page per
/// frame, when the panel opens again or when a surface asks for one of its
/// sprites, so [spriteOf] is null for a moment and the surface shows its
/// placeholder. A sprite is valid until the page is released: ask again to
/// draw.
///
/// A page the store cannot hand back is baked again once; if the second copy
/// cannot be read either, the page is given up on and its glyphs keep their
/// placeholder.
///
/// The atlas owns its residency, and disposes it in [dispose]; it does not own
/// the store, the rasteriser or the notifiers the host gave it.
///
/// ## Replacing an atlas without a gap
///
/// A plan cannot change in place, so a host that must plan again (a glyph
/// appeared that the plan lacks, the density changed) builds a second atlas.
/// [retire] stops this one and hands what it was drawing to the successor
/// ([predecessor]), which shows that art from its first frame, bakes its own
/// pages behind it and swaps once, as for a stale persisted set. Retiring also
/// lets the successor wait for this atlas's disk work to finish
/// ([RetiredGlyphArt.settled]), so two atlases never write one cache at once.
///
/// Platforms that do not bake never build one (see
/// `createGlyphAtlasForPlatform`): a surface without an atlas draws its glyphs
/// as text.
final class GlyphAtlas implements GlyphSpriteSource {
  /// Creates an atlas for the glyphs of [index]. Nothing runs until [start].
  ///
  /// Pass either a [store] (pages kept for this atlas's life only) or a
  /// [persistence] (pages kept across launches), not both. A [predecessor] is
  /// the art of the atlas this one replaces; see [retire].
  GlyphAtlas({
    required this.index,
    required GlyphRasteriser rasteriser,
    required BakeFrameSource frames,
    required BakeClock clock,
    required ValueListenable<bool> panelVisible,
    required ValueListenable<bool> panelOpening,
    GlyphPageStore? store,
    GlyphAtlasPersistence? persistence,
    BakeGovernor? governor,
    GlyphPageResidency? residency,
    GlyphBakeObserver? observer,
    RetiredGlyphArt? predecessor,
  }) : assert(
         (store == null) != (persistence == null),
         'give a GlyphAtlas a store or a persistence, exactly one',
       ),
       _persistence = persistence,
       _frames = frames,
       _clock = clock,
       _panelVisible = panelVisible,
       _panelOpening = panelOpening,
       _residency = residency ?? GlyphPageResidency(),
       _predecessorSettled = predecessor?.settled {
    _pageStore = _AtlasPageStore(
      store ?? MemoryGlyphPageStore(),
      persistent: persistence != null,
      ledger: _io,
    );
    _baker = GlyphBaker(
      index: index,
      rasteriser: rasteriser,
      store: _pageStore,
      observer: observer,
    );
    _pageStore.onComposed = _keepComposed;
    _pageStore.onWriteFailed = _reportWriteFailed;
    _signals = BakePauseSignals(
      panelVisible: panelVisible,
      scrolling: _scrolling,
      panelOpening: panelOpening,
    );
    _scheduler = GlyphBakeScheduler(
      baker: _baker,
      frames: frames,
      clock: clock,
      signals: _signals,
      governor: governor,
      onPageBaked: _load,
    );
    _residency
      ..addReleaseListener(_onReleased)
      ..addPressureListener(_onPressure);
    panelVisible.addListener(_onVisibleChanged);
    if (predecessor != null) _stale = predecessor._claimFor(index);
    _onVisibleChanged();
  }

  /// The plan being baked.
  final GlyphAtlasIndex index;

  final GlyphAtlasPersistence? _persistence;
  final BakeFrameSource _frames;
  final BakeClock _clock;
  final ValueListenable<bool> _panelVisible;
  final ValueListenable<bool> _panelOpening;
  final GlyphPageResidency _residency;
  final Future<void>? _predecessorSettled;
  final _IoLedger _io = _IoLedger();
  late final _AtlasPageStore _pageStore;
  late final GlyphBaker _baker;
  late final BakePauseSignals _signals;
  late final GlyphBakeScheduler _scheduler;
  final ValueNotifier<bool> _scrolling = ValueNotifier<bool>(false);
  // The surfaces that reported motion and have not yet reported it over.
  final Set<Object> _scrollers = <Object>{};
  _Lifecycle _lifecycle = _Lifecycle.created;

  // Sprites already cut, so a repaint allocates nothing. An entry is used only
  // while its page is still the image the residency holds.
  final Map<String, AtlasSprite> _sprites = <String, AtlasSprite>{};
  final List<ValueChanged<int>> _listeners = <ValueChanged<int>>[];
  // Pages being read from the store (queued or in flight), and how many times
  // a page could not be handed back: the first failure bakes it again, the
  // second gives up (a store that failed twice will fail again).
  final Set<int> _loading = <int>{};
  final Map<int, int> _readFailures = <int, int>{};
  // Pages waiting for their paced reload, and the loop that drains them.
  final List<int> _reloads = <int>[];
  Future<void>? _reloadPump;
  // Wake-ups of everything waiting on a frame or on a calm moment, so dispose
  // can end the wait at once.
  final Set<VoidCallback> _sleepers = <VoidCallback>{};
  // The claim on every page while the panel is open.
  GlyphPageHold? _openHold;

  bool get _disposed => _lifecycle == _Lifecycle.disposed;

  /// The resident pages: their counts, retention and release. The cache's
  /// bindings hold pages through [holdPageOf]; this is for inspection.
  GlyphPageResidency get residency => _residency;

  /// Raw bytes of every page image this atlas holds: the resident pages plus
  /// the stale set still drawn while its replacement bakes.
  int get residentBytes => _residency.residentBytes + (_stale?.bytes ?? 0);

  // --- Persistence state (unused without a GlyphAtlasPersistence) -------------

  // Pages just composed, kept so a disk-backed store is not read back for
  // what the baker had in hand a moment ago.
  final Map<int, Image> _composed = <int, Image>{};
  // Pages of the current plan that have been drawable at least once; the swap
  // waits for all of them, however often a page is released and read again.
  final Set<int> _ready = <int>{};
  // The previous generation still being drawn while this plan bakes. Its
  // images are not in the residency: they are short-lived (one rebake) and
  // are dropped at the swap, on memory pressure or on dispose.
  _StaleSet? _stale;
  Duration? _startedAt;
  GlyphCacheReport _report = const GlyphCacheReport();

  /// What the persistent flow decided and how long its circles lasted; a
  /// report with a null verdict for an atlas without persistence or before the
  /// cache is read.
  GlyphCacheReport get cacheReport => _report;

  /// Starts baking, as far as the pause signals allow. Does nothing after
  /// [dispose] or when called twice.
  ///
  /// With persistence the bake starts once the cache has been read and
  /// restored; until then the glyphs show their placeholder.
  void start() {
    if (_lifecycle != _Lifecycle.created) return;
    _lifecycle = _Lifecycle.started;
    _startedAt = _clock();
    final persistence = _persistence;
    if (persistence == null) {
      _startBaking();
      return;
    }
    unawaited(_begin(persistence));
  }

  /// The sprite of [glyph], or null while its page is not baked and loaded,
  /// when the glyph is not in the catalogue, and after [dispose]: the caller
  /// shows a placeholder or paints the glyph itself.
  ///
  /// While a stale set is being replaced this is the old art for the glyphs it
  /// holds, and nothing of the new set until the swap.
  ///
  /// A baked page that is not resident (released after the retention or under
  /// memory pressure) is queued to be read back from the store, so this is
  /// not a pure read; listeners hear the page when it is drawable again.
  ///
  /// Allocation-free once a sprite has been cut: it runs for every visible
  /// leaf on every paint.
  @override
  AtlasSprite? spriteOf(String glyph) {
    if (_disposed) return null;
    final stale = _stale;
    if (stale != null) return stale.sprites[glyph];
    final cached = _sprites[glyph];
    if (cached != null &&
        identical(cached.page, _residency.imageOf(cached.pageIndex))) {
      return cached;
    }
    final placement = index.placementOf(glyph);
    if (placement == null) return null;
    final page = _residency.imageOf(placement.pageIndex);
    if (page == null) {
      _reloadIfBaked(placement.pageIndex);
      return null;
    }
    return _sprites[glyph] = AtlasSprite(
      pageIndex: placement.pageIndex,
      page: page,
      source: placement.source,
    );
  }

  /// Claims the page [glyph] is on, for as long as the caller (a leaf binding)
  /// is bound to it, or returns null when the glyph is not in the catalogue.
  ///
  /// The page stays resident while any claim covers it; release the hold when
  /// unbound. It holds a count, not pixels: ask [spriteOf] when drawing.
  @override
  GlyphPageHold? holdPageOf(String glyph) {
    if (_disposed) return null;
    final page = index.placementOf(glyph)?.pageIndex;
    return page == null ? null : _residency.hold(page);
  }

  /// Calls [listener] with the index of each page whose drawability changed:
  /// once its sprites can be drawn, and again when the page is released (a
  /// surface repaints either way).
  @override
  void addPageListener(ValueChanged<int> listener) => _listeners.add(listener);

  /// Removes a listener added with [addPageListener].
  @override
  void removePageListener(ValueChanged<int> listener) =>
      _listeners.remove(listener);

  /// Tells the atlas whether the surface [reporter] draws on is scrolling, so
  /// baking stays out of the way of the motion. Report `false` again once it
  /// settled and when the surface goes away.
  ///
  /// Several surfaces can share one atlas, so motion is the union of what they
  /// report: one that settles does not resume baking under another that is
  /// still moving. [reporter] identifies the surface; any object that is the
  /// same for every report of that surface will do.
  void reportScrolling({required Object reporter, required bool scrolling}) {
    if (_disposed) return;
    if (scrolling) {
      _scrollers.add(reporter);
    } else {
      _scrollers.remove(reporter);
    }
    _scrolling.value = _scrollers.isNotEmpty;
  }

  /// Says which glyphs are on screen, most important first; the pages holding
  /// them bake before the others. Call it when scrolling settles.
  void prioritise(Iterable<String> glyphs) {
    if (_disposed) return;
    _scheduler.prioritise(glyphs);
  }

  /// Stops baking and releases the page images. Idempotent. Pages in the store
  /// stay there.
  void dispose() {
    if (_disposed) return;
    _shutdown();
  }

  /// Stops this atlas like [dispose], but gives the art it was drawing to a
  /// successor instead of releasing it, so a surface moved to the successor
  /// shows no gap. See "Replacing an atlas without a gap" above.
  ///
  /// What is handed over is what [spriteOf] answers right now: the resident
  /// pages, or the stale set when one is still being drawn. Pages the bake had
  /// not finished are not part of it. Whoever gets the [RetiredGlyphArt] must
  /// pass it to a successor or [RetiredGlyphArt.dispose] it.
  RetiredGlyphArt retire() {
    final art = _StaleSet();
    if (!_disposed) {
      final stale = _stale;
      if (stale != null) {
        art.pages.addAll(stale.pages);
        art.sprites.addAll(stale.sprites);
        stale.pages.clear();
        stale.sprites.clear();
      } else {
        for (final page in _residency.residentPages) {
          final image = _residency.takeImage(page);
          if (image == null) continue;
          art.pages[page] = image;
          for (final glyph in index.glyphsOnPage(page)) {
            art.sprites[glyph] = AtlasSprite(
              pageIndex: page,
              page: image,
              source: index.placementOf(glyph)!.source,
            );
          }
        }
      }
    }
    final settled = _io.settled;
    dispose();
    return RetiredGlyphArt._(art, settled);
  }

  void _shutdown() {
    _lifecycle = _Lifecycle.disposed;
    _panelVisible.removeListener(_onVisibleChanged);
    _openHold?.release();
    _openHold = null;
    for (final wake in List<VoidCallback>.of(_sleepers)) {
      wake();
    }
    _scheduler.dispose();
    _baker.dispose();
    _sprites.clear();
    for (final page in _composed.values) {
      page.dispose();
    }
    _composed.clear();
    _reloads.clear();
    _stale?.release();
    _stale = null;
    _listeners.clear();
    _residency.dispose();
    _scrolling.dispose();
  }

  // The panel being open holds every page; closing it starts the retention.
  void _onVisibleChanged() {
    if (_disposed) return;
    if (_panelVisible.value) {
      if (_openHold != null) return;
      _openHold = _residency.holdAll();
      for (var page = 0; page < index.pageCount; page++) {
        _reloadIfBaked(page);
      }
    } else {
      _openHold?.release();
      _openHold = null;
    }
  }

  void _startBaking() {
    _scheduler.start();
    if (_stale != null && index.pageCount == 0) unawaited(_swap());
  }

  // --- Loading pages ------------------------------------------------------------

  /// Queues the paced reload of a page that was baked and is no longer
  /// resident (released after the retention or under memory pressure).
  void _reloadIfBaked(int pageIndex) {
    if (!_baker.isPageBaked(pageIndex) ||
        _residency.isResident(pageIndex) ||
        _loading.contains(pageIndex) ||
        _gaveUpOn(pageIndex)) {
      return;
    }
    _loading.add(pageIndex);
    _reloads.add(pageIndex);
    _reloadPump ??= _pumpReloads();
  }

  /// Reads the queued pages back, one per frame and never in a scroll or the
  /// open animation, like the restore of a persisted set.
  Future<void> _pumpReloads() async {
    while (_reloads.isNotEmpty) {
      if (!await _awaitRestoreFrame()) break;
      if (_reloads.isEmpty) break;
      final page = _reloads.removeAt(0);
      if (_residency.isResident(page)) {
        _loading.remove(page);
        continue;
      }
      await _read(page);
    }
    _reloadPump = null;
  }

  void _onReleased(int pageIndex) {
    index.glyphsOnPage(pageIndex).forEach(_sprites.remove);
    _notify(pageIndex);
  }

  // Memory pressure also takes the stale images, which the residency does not
  // hold: they are as much memory as the pages it just released.
  void _onPressure() {
    final stale = _stale;
    if (stale == null) return;
    stale.release().forEach(_notify);
  }

  void _notify(int pageIndex) {
    for (final listener in List<ValueChanged<int>>.of(_listeners)) {
      listener(pageIndex);
    }
  }

  /// Takes the page the baker has just composed into the residency.
  void _load(int pageIndex) {
    if (_disposed || _loading.contains(pageIndex) || _gaveUpOn(pageIndex)) {
      // The clone shares the native image: left in [_composed] it would keep a
      // whole page alive past the residency's release.
      _composed.remove(pageIndex)?.dispose();
      return;
    }
    _loading.add(pageIndex);
    unawaited(_read(pageIndex));
  }

  Future<void> _read(int pageIndex) async {
    // A persistent atlas kept the composed page; otherwise it is read back.
    var image = _composed.remove(pageIndex);
    if (image == null) {
      try {
        image = await _pageStore.read(pageIndex);
        if (image == null) {
          throw StateError('The page store has no page $pageIndex to read.');
        }
      } on Object catch (error, stack) {
        _loading.remove(pageIndex);
        _fail(error, stack, 'while loading glyph atlas page $pageIndex');
        _bakeAgainOrGiveUp(pageIndex);
        return;
      }
    }
    _loading.remove(pageIndex);
    _admit(pageIndex, image);
  }

  /// A page the store could not hand back is baked again, once: the baker has
  /// the glyphs, and a transient fault should not leave circles for the life
  /// of the process. A second failure means the store cannot be trusted with
  /// this page; it is left unbaked, and reported both times.
  void _bakeAgainOrGiveUp(int pageIndex) {
    final failures = _readFailures[pageIndex] = _failuresOf(pageIndex) + 1;
    if (_disposed) return;
    if (failures > 1) {
      _swapIfSettled();
      return;
    }
    _baker.markUnbaked(pageIndex);
    _scheduler.resume();
  }

  /// Starts the swap once every page of the plan is either drawable or given
  /// up on. Waiting for a page that will never load would keep the stale set,
  /// and the memory of both sets, for the rest of the process; swapping leaves
  /// that page's glyphs as placeholders, which is what a given-up page is
  /// anyway. A plan with no drawable page keeps the stale art: a bare
  /// placeholder grid is worse than the old glyphs.
  void _swapIfSettled() {
    if (_stale == null || _ready.isEmpty) return;
    for (var page = 0; page < index.pageCount; page++) {
      if (!_ready.contains(page) && !_gaveUpOn(page)) return;
    }
    unawaited(_swap());
  }

  int _failuresOf(int pageIndex) => _readFailures[pageIndex] ?? 0;

  bool _gaveUpOn(int pageIndex) => _failuresOf(pageIndex) > 1;

  /// Takes ownership of [image] as page [pageIndex] of the current plan.
  void _admit(int pageIndex, Image image) {
    if (_disposed) {
      // The atlas went away while the page was on its way; nobody can draw it.
      image.dispose();
      return;
    }
    _residency.admit(pageIndex, image);
    _ready.add(pageIndex);
    // Behind a stale set the new pages wait for the swap.
    if (_stale != null) {
      _swapIfSettled();
      return;
    }
    _noteVisible(complete: _ready.length == index.pageCount);
    _notify(pageIndex);
  }

  // --- Persistence -------------------------------------------------------------

  Future<void> _begin(GlyphAtlasPersistence persistence) async {
    // One writer at a time: the atlas this one replaces may still be writing
    // pages into the same cache.
    await _predecessorSettled;
    if (_disposed) return;
    try {
      await _decideAndRestore(persistence);
    } on Object catch (error, stack) {
      // Last resort: whatever went wrong, the bake still runs, in memory.
      _fail(error, stack, 'while restoring the glyph atlas cache');
      _pageStore.useMemory();
    }
    if (_disposed) return;
    _startBaking();
  }

  Future<void> _decideAndRestore(GlyphAtlasPersistence persistence) async {
    final String art;
    try {
      art = await persistence.artVersion.read();
    } on Object catch (error, stack) {
      // Without the art version nothing persisted can be trusted and nothing
      // new can be filed under a key: this launch bakes into memory only.
      _fail(error, stack, 'while reading the system emoji art version');
      _pageStore.useMemory();
      return;
    }
    if (_disposed) return;

    final key = GlyphCacheKey(
      artVersion: art,
      devicePixelRatio: persistence.devicePixelRatio,
      glyphSize: index.layout.glyphSize,
      layoutVersion: GlyphAtlasLayout.version,
      catalogueHash: GlyphCacheKey.catalogueHashOf(index.glyphs),
    );
    final record = GlyphCacheRecord(key: key, glyphs: index.glyphs);
    final cache = persistence.cache;

    GlyphCacheGeneration? committed;
    try {
      committed = await _io.track(cache.openCommitted());
    } on Object catch (error, stack) {
      _fail(error, stack, 'while opening the glyph atlas cache');
    }
    if (_disposed) return;

    final verdict = committed == null
        ? GlyphCacheVerdict.miss
        : key.verdictAgainst(committed.record.key);
    _report = GlyphCacheReport(verdict: verdict);

    try {
      switch (verdict) {
        case GlyphCacheVerdict.hit:
          // The persisted set is exactly this plan: art inherited from a
          // predecessor is moot.
          _stale?.release();
          _stale = null;
          _pageStore.generation = committed!.pages;
          await _restoreHit(committed.pages);
        case GlyphCacheVerdict.stale:
          // Art inherited from a predecessor is newer than the persisted set
          // and is already in memory: keep it, skip reading the old pages.
          if (_stale == null) await _loadStale(committed!);
          if (_disposed) return;
          _stale?.commitOnSwap = true;
          _pageStore.generation = await _io.track(cache.stage(record));
        case GlyphCacheVerdict.discard:
        case GlyphCacheVerdict.miss:
          _pageStore.generation = await _io.track(cache.stage(record));
          // Committed at once: each page is durable as soon as it is written,
          // and a launch after a kill restores the pages that made it.
          await _io.track(cache.commit());
      }
    } on Object catch (error, stack) {
      _fail(error, stack, 'while preparing the glyph atlas cache');
      _pageStore.useMemory();
    }
  }

  /// Reads the persisted pages of this plan back, one per frame.
  Future<void> _restoreHit(GlyphPageStore pages) async {
    var restored = 0;
    for (var page = 0; page < index.pageCount; page++) {
      if (!await _awaitRestoreFrame()) return;
      final image = await _readOrNull(pages, page);
      if (_disposed) {
        image?.dispose();
        return;
      }
      if (image == null) continue;
      _baker.markBaked(page);
      restored++;
      _report = _copyReport(restoredPages: restored);
      _admit(page, image);
    }
  }

  /// Reads the previous generation back, one page per frame, to keep drawing
  /// it while this plan bakes.
  Future<void> _loadStale(GlyphCacheGeneration committed) async {
    final old = GlyphAtlasIndex(
      committed.record.glyphs,
      layout: GlyphAtlasLayout(glyphSize: committed.record.key.glyphSize),
    );
    final stale = _stale = _StaleSet();
    for (var page = 0; page < old.pageCount; page++) {
      if (!await _awaitRestoreFrame()) return;
      final image = await _readOrNull(committed.pages, page);
      if (_disposed) {
        image?.dispose();
        return;
      }
      if (image == null) continue;
      stale.pages[page] = image;
      for (final glyph in old.glyphsOnPage(page)) {
        // Only glyphs the current plan still draws: the catalogue contract is
        // that a glyph outside it has no sprite.
        if (index.placementOf(glyph) == null) continue;
        stale.sprites[glyph] = AtlasSprite(
          pageIndex: page,
          page: image,
          source: old.placementOf(glyph)!.source,
        );
      }
      _report = _copyReport(stalePages: stale.pages.length);
      _noteVisible(complete: false);
      _notify(page);
    }
  }

  /// Replaces the stale set by the new one in a single step.
  Future<void> _swap() async {
    final stale = _stale;
    if (stale == null || stale.swapping || _disposed) return;
    stale.swapping = true;
    if (stale.commitOnSwap && _pageStore.onDisk) {
      try {
        await _io.track(_persistence!.cache.commit());
      } on Object catch (error, stack) {
        _fail(error, stack, 'while committing the glyph atlas cache');
      }
    }
    if (_disposed || !identical(_stale, stale)) return;
    // Everything below is synchronous: no frame sees half of the swap.
    _stale = null;
    stale.release();
    _report = _copyReport(swapped: true);
    _noteVisible(complete: true);
    for (var page = 0; page < index.pageCount; page++) {
      _notify(page);
    }
  }

  Future<Image?> _readOrNull(GlyphPageStore pages, int page) async {
    try {
      return await _io.track(pages.read(page));
    } on Object catch (error, stack) {
      _fail(error, stack, 'while reading glyph atlas page $page from disk');
      return null;
    }
  }

  // --- Waiting for a calm frame ----------------------------------------------------

  bool get _isMoving => _scrolling.value || _panelOpening.value;

  /// Completes at the next frame on which restoring may run, or returns false
  /// once the atlas is disposed. Reading a page is real work on the root
  /// isolate, so it never lands in a scroll or the open animation.
  Future<bool> _awaitRestoreFrame() async {
    while (!_disposed) {
      if (_isMoving) {
        await _untilCalm();
        continue;
      }
      await _untilNextFrame();
      if (_disposed) return false;
      // The user may have started moving while the frame was coming.
      if (!_isMoving) return true;
    }
    return false;
  }

  Future<void> _untilNextFrame() =>
      _sleep((wake) => _frames.requestFrame((_) => wake()));

  Future<void> _untilCalm() => _sleep((wake) {
    final moving = Listenable.merge(<Listenable>[_scrolling, _panelOpening]);
    void check() {
      if (!_isMoving) wake();
    }

    moving.addListener(check);
    return () => moving.removeListener(check);
  });

  /// Waits until the armed condition calls `wake`, or the atlas is disposed.
  /// [arm] starts watching and returns how to stop.
  Future<void> _sleep(VoidCallback Function(VoidCallback wake) arm) {
    final done = Completer<void>();
    late final VoidCallback disarm;
    void wake() {
      _sleepers.remove(wake);
      disarm();
      if (!done.isCompleted) done.complete();
    }

    disarm = arm(wake);
    _sleepers.add(wake);
    return done.future;
  }

  // --- Reporting ------------------------------------------------------------------

  void _noteVisible({required bool complete}) {
    final started = _startedAt;
    if (started == null) return;
    final elapsed = _clock() - started;
    _report = _copyReport(
      firstPageAfterStart: _report.firstPageAfterStart ?? elapsed,
      allPagesAfterStart: complete
          ? (_report.allPagesAfterStart ?? elapsed)
          : _report.allPagesAfterStart,
    );
  }

  GlyphCacheReport _copyReport({
    int? restoredPages,
    int? stalePages,
    bool? swapped,
    Duration? firstPageAfterStart,
    Duration? allPagesAfterStart,
  }) => GlyphCacheReport(
    verdict: _report.verdict,
    restoredPages: restoredPages ?? _report.restoredPages,
    stalePages: stalePages ?? _report.stalePages,
    swapped: swapped ?? _report.swapped,
    firstPageAfterStart: firstPageAfterStart ?? _report.firstPageAfterStart,
    allPagesAfterStart: allPagesAfterStart ?? _report.allPagesAfterStart,
  );

  // --- The page store the baker writes to ---------------------------------------

  void _keepComposed(int pageIndex, Image clone) {
    if (_disposed) {
      clone.dispose();
      return;
    }
    _composed.remove(pageIndex)?.dispose();
    _composed[pageIndex] = clone;
  }

  void _reportWriteFailed(Object error, StackTrace stack) =>
      _fail(error, stack, 'while persisting a glyph atlas page');

  /// Reports a failure unless the atlas is already gone (a late fault of work
  /// nobody waits for any more is not news).
  void _fail(Object error, StackTrace stack, String doing) {
    if (_disposed) return;
    reportGlyphAtlasError(error, stack, doing);
  }
}

/// What an atlas draws, handed over by [GlyphAtlas.retire] to the atlas that
/// replaces it.
///
/// Holds page images, so it must end in exactly one of two ways: given to a
/// successor (`GlyphAtlas(predecessor: ...)`), which then owns it, or
/// [dispose]d.
final class RetiredGlyphArt {
  RetiredGlyphArt._(this._art, this.settled);

  final _StaleSet _art;

  /// Completes when the retired atlas has no disk operation left in flight. A
  /// successor over the same cache waits for it before touching the cache.
  /// Never completes with an error.
  final Future<void> settled;

  bool _claimed = false;

  /// Releases the art instead of handing it on. Idempotent.
  void dispose() {
    _claimed = true;
    _art.release();
  }

  /// The part of the art a plan can still draw, as a stale set; the pages
  /// nothing of the plan uses are released here.
  _StaleSet _claimFor(GlyphAtlasIndex index) {
    assert(!_claimed, 'retired art can be given to one successor only');
    _claimed = true;
    final kept = _StaleSet();
    for (final entry in _art.sprites.entries) {
      // The catalogue contract: a glyph outside the plan has no sprite.
      if (index.placementOf(entry.key) != null) {
        kept.sprites[entry.key] = entry.value;
      }
    }
    final used = <int>{
      for (final sprite in kept.sprites.values) sprite.pageIndex,
    };
    for (final entry in _art.pages.entries) {
      if (used.contains(entry.key)) {
        kept.pages[entry.key] = entry.value;
      } else {
        entry.value.dispose();
      }
    }
    _art.pages.clear();
    _art.sprites.clear();
    return kept;
  }
}

/// Where an atlas is in its life: it cannot be disposed before it was created
/// or start twice.
enum _Lifecycle { created, started, disposed }

/// The disk work an atlas has started and not yet seen finish.
///
/// A retired atlas stops starting work, but what it already started (a page
/// write, a commit) runs on; its successor must not touch the same cache until
/// that is over, because a cache store has a single writer.
final class _IoLedger {
  final Set<Future<void>> _inFlight = <Future<void>>{};

  /// Records [operation] until it completes, then returns it unchanged.
  Future<T> track<T>(Future<T> operation) {
    final done = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _inFlight.add(done);
    unawaited(done.whenComplete(() => _inFlight.remove(done)));
    return operation;
  }

  /// Completes when nothing is in flight, including work started meanwhile.
  Future<void> get settled async {
    while (_inFlight.isNotEmpty) {
      await Future.wait(_inFlight.toList());
    }
  }
}

/// The store the baker writes to and the atlas reads from: a plain
/// pass-through for an atlas with its own store; for a persistent one, a
/// write-through that keeps the composed page for the atlas (so a disk store
/// is not read back) and turns a failing disk into a report instead of a
/// stopped bake. The target is chosen when the cache has been read.
final class _AtlasPageStore implements GlyphPageStore {
  _AtlasPageStore(
    this._target, {
    required this.persistent,
    required this.ledger,
  }) : onDisk = persistent;

  GlyphPageStore _target;
  final bool persistent;
  final _IoLedger ledger;
  void Function(int pageIndex, Image clone)? onComposed;
  void Function(Object error, StackTrace stack)? onWriteFailed;

  /// Whether the pages being written still go to a persisted generation: false
  /// for an atlas without persistence, after the disk failed, and when the
  /// cache could not be used and the pages live in memory only. A generation
  /// that is not on disk is never committed.
  bool onDisk;

  /// Sends the pages to the generation of the cache set here.
  set generation(GlyphPageStore pages) => _target = pages;

  /// Keeps the pages in memory for this atlas's life; nothing is persisted.
  void useMemory() {
    _target = MemoryGlyphPageStore();
    onDisk = false;
  }

  @override
  Future<void> write(int pageIndex, Image page) async {
    if (!persistent) return ledger.track(_target.write(pageIndex, page));
    onComposed?.call(pageIndex, page.clone());
    try {
      await ledger.track(_target.write(pageIndex, page));
    } on Object catch (error, stack) {
      // Reported once: a disk that refuses a page refuses the next one too.
      if (onDisk) {
        onDisk = false;
        onWriteFailed?.call(error, stack);
      }
    }
  }

  @override
  Future<Image?> read(int pageIndex) => ledger.track(_target.read(pageIndex));

  @override
  Future<void> clear() => _target.clear();
}

/// The previous generation, drawn while the new one bakes.
final class _StaleSet {
  final Map<int, Image> pages = <int, Image>{};
  final Map<String, AtlasSprite> sprites = <String, AtlasSprite>{};

  /// Whether the replacement is a staged generation that the swap must commit
  /// (art or catalogue changed). False when it was committed as it started
  /// (first run, discard) or is not persisted at all.
  bool commitOnSwap = false;

  /// Whether the swap has started; it waits on the commit, and a second page
  /// completing meanwhile must not start another.
  bool swapping = false;

  /// Raw bytes of the images held.
  int get bytes => pages.values.fold<int>(
    0,
    (sum, image) =>
        sum + image.width * image.height * GlyphAtlasLayout.bytesPerPixel,
  );

  /// Disposes the images and forgets the sprites, keeping the set itself (a
  /// stale set released by memory pressure still stands for "the replacement
  /// is not swapped in yet"). Returns the pages that were released.
  List<int> release() {
    final released = pages.keys.toList();
    sprites.clear();
    for (final page in pages.values) {
      page.dispose();
    }
    pages.clear();
    return released;
  }
}
