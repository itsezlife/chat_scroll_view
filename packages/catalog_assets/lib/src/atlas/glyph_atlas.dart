import 'dart:async';
import 'dart:ui';

import 'package:catalog_assets/src/atlas/atlas_sprite.dart';
import 'package:catalog_assets/src/atlas/bake_frame_source.dart';
import 'package:catalog_assets/src/atlas/bake_governor.dart';
import 'package:catalog_assets/src/atlas/bake_pause_signals.dart';
import 'package:catalog_assets/src/atlas/glyph_atlas_index.dart';
import 'package:catalog_assets/src/atlas/glyph_bake_scheduler.dart';
import 'package:catalog_assets/src/atlas/glyph_baker.dart';
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
/// The atlas owns the page images it hands out, and its sprites are valid
/// until [dispose]; it does not own the store, the rasteriser or the notifiers
/// the host gave it. Page ownership by reference count moves into the asset
/// cache later; until then one atlas serves one host.
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
  }) : _store = store,
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
      onPageBaked: _onPageBaked,
    );
  }

  /// The plan being baked.
  final GlyphAtlasIndex index;

  final GlyphPageStore _store;
  final GlyphBaker _baker;
  late final BakePauseSignals _signals;
  late final GlyphBakeScheduler _scheduler;
  final ValueNotifier<bool> _scrolling = ValueNotifier<bool>(false);

  // Resident pages and the sprites cut from them. A sprite exists only while
  // its page image is held here, so a lookup never returns a disposed image.
  final Map<int, Image> _pages = <int, Image>{};
  final Map<String, AtlasSprite> _sprites = <String, AtlasSprite>{};
  final List<ValueChanged<int>> _listeners = <ValueChanged<int>>[];
  bool _disposed = false;

  /// Starts baking, as far as the pause signals allow. Does nothing after
  /// [dispose] or when called twice.
  void start() => _scheduler.start();

  /// The sprite of [glyph], or null while its page is not baked and loaded,
  /// when the glyph is not in the catalogue, and after [dispose]: the caller
  /// shows a placeholder or paints the glyph itself.
  AtlasSprite? spriteOf(String glyph) => _sprites[glyph];

  /// Calls [listener] with the index of each page once its sprites can be
  /// drawn.
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
    _scheduler.dispose();
    _baker.dispose();
    _sprites.clear();
    for (final page in _pages.values) {
      page.dispose();
    }
    _pages.clear();
    _listeners.clear();
    _scrolling.dispose();
  }

  void _onPageBaked(int pageIndex) => unawaited(_loadPage(pageIndex));

  Future<void> _loadPage(int pageIndex) async {
    Image? image;
    try {
      image = await _store.read(pageIndex);
      if (image == null) {
        throw StateError(
          'The page store has no page $pageIndex right after it was written.',
        );
      }
    } on Object catch (error, stack) {
      // A page that cannot be read back stays unbaked: its glyphs keep their
      // placeholder. Reported rather than retried, as a store that failed once
      // will fail again.
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
    if (_disposed) {
      // The atlas went away while the page was on its way; nobody can draw it.
      image.dispose();
      return;
    }
    _pages.remove(pageIndex)?.dispose();
    _pages[pageIndex] = image;
    for (final glyph in index.glyphsOnPage(pageIndex)) {
      _sprites[glyph] = AtlasSprite(
        pageIndex: pageIndex,
        page: image,
        source: index.placementOf(glyph)!.source,
      );
    }
    for (final listener in List<ValueChanged<int>>.of(_listeners)) {
      listener(pageIndex);
    }
  }
}
