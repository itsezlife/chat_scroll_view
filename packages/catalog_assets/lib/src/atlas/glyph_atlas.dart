import 'dart:async';
import 'dart:ui';

import 'package:catalog_assets/src/atlas/atlas_sprite.dart';
import 'package:catalog_assets/src/atlas/bake_frame_source.dart';
import 'package:catalog_assets/src/atlas/bake_governor.dart';
import 'package:catalog_assets/src/atlas/bake_pause_signals.dart';
import 'package:catalog_assets/src/atlas/glyph_atlas_index.dart';
import 'package:catalog_assets/src/atlas/glyph_bake_scheduler.dart';
import 'package:catalog_assets/src/atlas/glyph_baker.dart';
import 'package:catalog_assets/src/atlas/glyph_page_residency.dart';
import 'package:catalog_assets/src/atlas/glyph_page_store.dart';
import 'package:catalog_assets/src/atlas/glyph_rasteriser.dart';
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
  GlyphAtlas({
    required this.index,
    required GlyphRasteriser rasteriser,
    required GlyphPageStore store,
    required BakeFrameSource frames,
    required BakeClock clock,
    required ValueListenable<bool> panelVisible,
    required ValueListenable<bool> panelOpening,
    BakeGovernor? governor,
    GlyphPageResidency? residency,
  }) : _store = store,
       _panelVisible = panelVisible,
       _residency = residency ?? GlyphPageResidency(),
       _baker = GlyphBaker(index: index, rasteriser: rasteriser, store: store) {
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

  final GlyphPageStore _store;
  final ValueListenable<bool> _panelVisible;
  final GlyphPageResidency _residency;
  final GlyphBaker _baker;
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
  bool _disposed = false;

  /// The resident pages: their counts, retention and release. The cache's
  /// bindings hold pages through [holdPageOf]; this is for inspection.
  GlyphPageResidency get residency => _residency;

  /// Starts baking, as far as the pause signals allow. Does nothing after
  /// [dispose] or when called twice.
  void start() => _scheduler.start();

  /// The sprite of [glyph], or null while its page is not baked and loaded,
  /// when the glyph is not in the catalogue, and after [dispose]: the caller
  /// shows a placeholder or paints the glyph itself.
  ///
  /// A baked page that is not resident (released after the retention or under
  /// memory pressure) is read back from the store now, which is why this is
  /// not a pure read; listeners hear the page when it is drawable again.
  AtlasSprite? spriteOf(String glyph) {
    if (_disposed) return null;
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
    _scheduler.dispose();
    _baker.dispose();
    _sprites.clear();
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
    Image? image;
    try {
      image = await _store.read(pageIndex);
      if (image == null) {
        throw StateError('The page store has no page $pageIndex to read.');
      }
    } on Object catch (error, stack) {
      // A page that cannot be read back stays unbaked: its glyphs keep their
      // placeholder. Reported rather than retried.
      _loading.remove(pageIndex);
      _unreadable.add(pageIndex);
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'catalog_assets',
          context: ErrorDescription(
            'while loading glyph atlas page $pageIndex',
          ),
        ),
      );
      return;
    }
    _loading.remove(pageIndex);
    if (_disposed) {
      // The atlas went away while the page was on its way; nobody can draw it.
      image.dispose();
      return;
    }
    _residency.admit(pageIndex, image);
    _notify(pageIndex);
  }
}
