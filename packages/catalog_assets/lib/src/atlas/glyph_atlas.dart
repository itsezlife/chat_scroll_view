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
/// Baking runs only while the panel is visible, nothing scrolls and the panel
/// is not opening ([BakePauseSignals]). The host owns the first and the last
/// as [panelVisible] and [panelOpening]; the surface that scrolls reports the
/// middle one through [reportScrolling] and says what is on screen through
/// [prioritise], because only it knows.
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
///   change. The stale images are outside the [residency] (they live for one
///   rebake and are dropped at the swap), so memory pressure does not release
///   them; the new pages are resident as usual;
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
/// its retention after the last hold goes, and releases them at once under
/// memory pressure. A released page is read back from the store when the
/// panel opens again or when a surface asks for one of its sprites, so
/// [spriteOf] is null for a moment and the surface shows its placeholder. A
/// sprite is valid until the page is released: ask again to draw.
///
/// The atlas owns its residency, and disposes it in [dispose]; it does not own
/// the store, the rasteriser or the notifiers the host gave it.
///
/// Platforms that do not bake never build one (see
/// `createGlyphAtlasForPlatform`): a surface without an atlas draws its glyphs
/// as text.
final class GlyphAtlas {
  /// Creates an atlas for the glyphs of [index]. Nothing runs until [start].
  ///
  /// Pass either a [store] (pages kept for this atlas's life only) or a
  /// [persistence] (pages kept across launches), not both.
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
       _pageStore = _AtlasPageStore(
         store ?? MemoryGlyphPageStore(),
         resident: persistence != null,
       ) {
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
    _residency.addReleaseListener(_onReleased);
    panelVisible.addListener(_onVisibleChanged);
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
  final _AtlasPageStore _pageStore;
  late final GlyphBaker _baker;
  late final BakePauseSignals _signals;
  late final GlyphBakeScheduler _scheduler;
  final ValueNotifier<bool> _scrolling = ValueNotifier<bool>(false);

  // Sprites already cut, so a repaint allocates nothing. An entry is used only
  // while its page is still the image the residency holds.
  final Map<String, AtlasSprite> _sprites = <String, AtlasSprite>{};
  final List<ValueChanged<int>> _listeners = <ValueChanged<int>>[];
  // Pages being read from the store, and pages the store could not hand back
  // (reported once, never retried: a store that failed will fail again).
  final Set<int> _loading = <int>{};
  final Set<int> _unreadable = <int>{};
  // The claim on every page while the panel is open.
  GlyphPageHold? _openHold;
  bool _started = false;
  bool _disposed = false;

  /// The resident pages: their counts, retention and release. The cache's
  /// bindings hold pages through [holdPageOf]; this is for inspection.
  GlyphPageResidency get residency => _residency;

  // --- Persistence state (unused without a GlyphAtlasPersistence) -------------

  // Pages just composed, kept so a disk-backed store is not read back for
  // what the baker had in hand a moment ago.
  final Map<int, Image> _composed = <int, Image>{};
  // Pages of the current plan that have been drawable at least once; the swap
  // waits for all of them, however often a page is released and read again.
  final Set<int> _ready = <int>{};
  // The previous generation still being drawn while this plan bakes. Its
  // images are not in the residency: they are short-lived (one rebake) and
  // are dropped at the swap or on dispose.
  _StaleSet? _stale;
  bool _writeFailed = false;
  bool _swapping = false;
  Duration? _startedAt;
  GlyphCacheReport _report = const GlyphCacheReport();
  Completer<void>? _restoreWake;
  BakeFrameCancel? _restoreCancel;

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
    if (_started || _disposed) return;
    _started = true;
    _startedAt = _clock();
    if (_persistence == null) {
      _scheduler.start();
      return;
    }
    unawaited(_begin(_persistence));
  }

  /// The sprite of [glyph], or null while its page is not baked and loaded,
  /// when the glyph is not in the catalogue, and after [dispose]: the caller
  /// shows a placeholder or paints the glyph itself.
  ///
  /// While a stale set is being replaced this is the old art for the glyphs it
  /// holds, and nothing of the new set until the swap.
  ///
  /// A baked page that is not resident (released after the retention or under
  /// memory pressure) is read back from the store now, which is why this is
  /// not a pure read; listeners hear the page when it is drawable again.
  AtlasSprite? spriteOf(String glyph) {
    if (_disposed) return null;
    final stale = _stale;
    if (stale != null) return stale.sprites[glyph];
    final placement = index.placementOf(glyph);
    if (placement == null) return null;
    final page = _residency.imageOf(placement.pageIndex);
    if (page == null) {
      _reloadIfBaked(placement.pageIndex);
      return null;
    }
    final cached = _sprites[glyph];
    if (cached != null && identical(cached.page, page)) return cached;
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
  GlyphPageHold? holdPageOf(String glyph) {
    if (_disposed) return null;
    final page = index.placementOf(glyph)?.pageIndex;
    return page == null ? null : _residency.hold(page);
  }

  /// Calls [listener] with the index of each page whose drawability changed:
  /// once its sprites can be drawn, and again when the page is released (a
  /// surface repaints either way).
  void addPageListener(ValueChanged<int> listener) => _listeners.add(listener);

  /// Removes a listener added with [addPageListener].
  void removePageListener(ValueChanged<int> listener) =>
      _listeners.remove(listener);

  /// Tells the atlas whether the surface it draws on is scrolling, so baking
  /// stays out of the way of the motion. Report `false` again once it settled
  /// and when the surface goes away.
  void reportScrolling({required bool scrolling}) {
    if (_disposed) return;
    _scrolling.value = scrolling;
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
    _disposed = true;
    _panelVisible.removeListener(_onVisibleChanged);
    _openHold?.release();
    _openHold = null;
    _restoreCancel?.call();
    _restoreCancel = null;
    final wake = _restoreWake;
    if (wake != null && !wake.isCompleted) wake.complete();
    _scheduler.dispose();
    _baker.dispose();
    _sprites.clear();
    for (final page in _composed.values) {
      page.dispose();
    }
    _composed.clear();
    _stale?.dispose();
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

  void _reloadIfBaked(int pageIndex) {
    if (_baker.isPageBaked(pageIndex) && !_residency.isResident(pageIndex)) {
      _load(pageIndex);
    }
  }

  void _onReleased(int pageIndex) {
    for (final glyph in index.glyphsOnPage(pageIndex)) {
      _sprites.remove(glyph);
    }
    _notify(pageIndex);
  }

  void _notify(int pageIndex) {
    for (final listener in List<ValueChanged<int>>.of(_listeners)) {
      listener(pageIndex);
    }
  }

  void _load(int pageIndex) {
    if (_disposed ||
        _loading.contains(pageIndex) ||
        _unreadable.contains(pageIndex)) {
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
        // A page that cannot be read back stays unbaked: its glyphs keep their
        // placeholder. Reported rather than retried.
        _loading.remove(pageIndex);
        _unreadable.add(pageIndex);
        _reportError(error, stack, 'while loading glyph atlas page $pageIndex');
        return;
      }
    }
    _loading.remove(pageIndex);
    _admit(pageIndex, image);
  }

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
      if (_ready.length == index.pageCount) unawaited(_swap());
      return;
    }
    _noteVisible(complete: _ready.length == index.pageCount);
    _notify(pageIndex);
  }

  // --- Persistence -------------------------------------------------------------

  Future<void> _begin(GlyphAtlasPersistence persistence) async {
    try {
      await _decideAndRestore(persistence);
    } on Object catch (error, stack) {
      // Last resort: whatever went wrong, the bake still runs, in memory.
      _fail(error, stack, 'while restoring the glyph atlas cache');
      _pageStore.target = MemoryGlyphPageStore();
      _writeFailed = true;
    }
    if (_disposed) return;
    _scheduler.start();
    if (_stale != null && index.pageCount == 0) unawaited(_swap());
  }

  Future<void> _decideAndRestore(GlyphAtlasPersistence persistence) async {
    final String art;
    try {
      art = await persistence.artVersion.read();
    } on Object catch (error, stack) {
      // Without the art version nothing persisted can be trusted and nothing
      // new can be filed under a key: this launch bakes into memory only.
      _fail(error, stack, 'while reading the system emoji art version');
      _pageStore.target = MemoryGlyphPageStore();
      _writeFailed = true;
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
      committed = await cache.openCommitted();
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
          _pageStore.target = committed!.pages;
          await _restoreHit(committed.pages);
        case GlyphCacheVerdict.stale:
          await _loadStale(committed!);
          if (_disposed) return;
          _pageStore.target = await cache.stage(record);
        case GlyphCacheVerdict.discard:
        case GlyphCacheVerdict.miss:
          _pageStore.target = await cache.stage(record);
          // Committed at once: each page is durable as soon as it is written,
          // and a launch after a kill restores the pages that made it.
          await cache.commit();
      }
    } on Object catch (error, stack) {
      _fail(error, stack, 'while preparing the glyph atlas cache');
      _pageStore.target = MemoryGlyphPageStore();
      _writeFailed = true;
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
    if (_swapping || _disposed) return;
    _swapping = true;
    if (!_writeFailed) {
      try {
        await _persistence!.cache.commit();
      } on Object catch (error, stack) {
        _fail(error, stack, 'while committing the glyph atlas cache');
      }
    }
    final stale = _stale;
    if (_disposed || stale == null) return;
    // Everything below is synchronous: no frame sees half of the swap.
    _stale = null;
    stale.dispose();
    _report = _copyReport(swapped: true);
    _noteVisible(complete: true);
    for (var page = 0; page < index.pageCount; page++) {
      _notify(page);
    }
  }

  Future<Image?> _readOrNull(GlyphPageStore pages, int page) async {
    try {
      return await pages.read(page);
    } on Object catch (error, stack) {
      _fail(error, stack, 'while reading glyph atlas page $page from disk');
      return null;
    }
  }

  /// Completes at the next frame on which restoring may run, or returns false
  /// once the atlas is disposed. Reading a page is real work on the root
  /// isolate, so it never lands in a scroll or the open animation.
  Future<bool> _awaitRestoreFrame() async {
    while (!_disposed) {
      if (_scrolling.value || _panelOpening.value) {
        await _untilCalm();
        continue;
      }
      final frame = Completer<void>();
      _restoreWake = frame;
      _restoreCancel = _frames.requestFrame((_) {
        if (!frame.isCompleted) frame.complete();
      });
      await frame.future;
      _restoreCancel = null;
      if (_disposed) return false;
      // The user may have started moving while the frame was coming.
      if (!_scrolling.value && !_panelOpening.value) return true;
    }
    return false;
  }

  Future<void> _untilCalm() async {
    final wake = _restoreWake = Completer<void>();
    final moving = Listenable.merge(<Listenable>[_scrolling, _panelOpening]);
    void check() {
      if (!_scrolling.value && !_panelOpening.value && !wake.isCompleted) {
        wake.complete();
      }
    }

    moving.addListener(check);
    await wake.future;
    moving.removeListener(check);
  }

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

  void _reportWriteFailed(Object error, StackTrace stack) {
    // Once per atlas: a disk that refuses a page refuses the next one too.
    if (_writeFailed || _disposed) return;
    _writeFailed = true;
    _fail(error, stack, 'while persisting a glyph atlas page');
  }

  void _fail(Object error, StackTrace stack, String doing) {
    if (_disposed) return;
    _reportError(error, stack, doing);
  }

  void _reportError(Object error, StackTrace stack, String doing) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'catalog_assets',
        context: ErrorDescription(doing),
      ),
    );
  }
}

/// The store the baker writes to and the atlas reads from: a plain
/// pass-through for an atlas with its own store; for a persistent one, a
/// write-through that keeps the composed page for the atlas (so a disk store
/// is not read back) and turns a failing disk into a report instead of a
/// stopped bake. [target] is chosen when the cache has been read.
final class _AtlasPageStore implements GlyphPageStore {
  _AtlasPageStore(this.target, {required this.resident});

  GlyphPageStore target;
  final bool resident;
  void Function(int pageIndex, Image clone)? onComposed;
  void Function(Object error, StackTrace stack)? onWriteFailed;

  @override
  Future<void> write(int pageIndex, Image page) async {
    if (!resident) return target.write(pageIndex, page);
    onComposed?.call(pageIndex, page.clone());
    try {
      await target.write(pageIndex, page);
    } on Object catch (error, stack) {
      onWriteFailed?.call(error, stack);
    }
  }

  @override
  Future<Image?> read(int pageIndex) => target.read(pageIndex);

  @override
  Future<void> clear() => target.clear();
}

/// The previous generation, drawn while the new one bakes.
final class _StaleSet {
  final Map<int, Image> pages = <int, Image>{};
  final Map<String, AtlasSprite> sprites = <String, AtlasSprite>{};

  void dispose() {
    sprites.clear();
    for (final page in pages.values) {
      page.dispose();
    }
    pages.clear();
  }
}
