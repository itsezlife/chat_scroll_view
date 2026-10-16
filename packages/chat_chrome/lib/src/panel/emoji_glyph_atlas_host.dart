import 'dart:async';

import 'package:catalog_assets/glyph_atlas.dart';
import 'package:chat_chrome/src/panel/emoji_page.dart';
import 'package:emoji_data/emoji_data.dart';
import 'package:flutter/foundation.dart';
import 'package:panel_catalog/panel_catalog.dart';

/// Builds the atlas a [GlyphAtlasRequest] describes; the web counterpart
/// returns null.
typedef GlyphAtlasFactory = GlyphAtlas? Function(GlyphAtlasRequest request);

/// Owns the [GlyphAtlas] of the emoji grid for as long as the panel shell
/// lives, so closing and reopening the panel does not bake again.
///
/// The grid page is torn down every time the panel closes; the baked pages
/// must not be. This host sits above it: the shell builds one, tells it when
/// the panel is visible and opening ([panelVisible], [panelOpening]), and hands
/// [atlas] to each grid page it mounts.
///
/// ## What is planned
///
/// [sync] plans the glyphs the grid draws, because an atlas can only draw
/// glyphs it planned and the viewport never falls back to text where emoji are
/// baked: the catalogue in the data layer's order with the user's skin tones
/// applied, then the recents the catalogue does not hold (a tone variant the
/// user no longer has selected), sorted. Recents come last and sorted on
/// purpose: a recent that is also in the catalogue is drawn from the
/// catalogue's cell, and the cache key hashes the plan, so a plan that followed
/// the recents' order would re-bake every page whenever the user picked
/// something.
///
/// When a glyph appears that is not planned (a tone chosen for the first
/// time, a recent the catalogue lacks) or the density changes
/// ([devicePixelRatio]), the atlas is planned again and listeners are told.
/// The new atlas takes over what the old one was drawing
/// ([GlyphAtlas.retire]), so the grid never goes blank: it shows the old art
/// for the glyphs both plans hold while the new pages bake, and swaps once.
/// The old atlas stops before the new one touches the cache, so a persistent
/// cache always has one writer.
///
/// ## The glyph-support probe
///
/// An [observer] (a `GlyphProbeBakeObserver` over a `MissingGlyphProbe`) is
/// shown every glyph the bake draws, so which glyphs the system cannot draw is
/// learned in the same pass that bakes them. The atlas still plans the
/// unfiltered glyph list: a glyph the probe flags keeps its cell (a box nobody
/// draws), because filtering the plan would make the cache key depend on the
/// probe's result and re-bake every page once the probe finishes. The grid
/// hides the glyph by filtering its *data* (`GlyphProbeEmojiPlatformFilter`).
///
/// ## Persistence
///
/// Given a [GlyphAtlasPersistence] the baked pages outlive the process: a
/// later launch restores them instead of baking, and an OS or font update
/// re-bakes behind the old pages. The host never clears the persisted pages
/// (they are the point); a host that wants them gone clears its own cache
/// store. Without one, every atlas keeps its pages in a store of its own (from
/// `newStore`), cleared when the atlas is replaced or the host disposed.
///
/// ## How long the pages stay
///
/// The pages are not kept for the life of the shell. Each atlas gets a
/// [GlyphPageResidency] that holds them while the panel is open and for
/// `pageRetention` after it closes (60 seconds unless the host says
/// otherwise), and releases them at once when `memoryPressure` fires.
/// Reopening within the retention needs no reload; after it, or after
/// pressure, the pages are read back from the store. With the default
/// in-memory store the texture stays alive behind the store's own handle, so
/// release frees the handles but not the bytes; a store that persists pages
/// off the heap (the disk cache) is what returns the memory.
///
/// On a platform that does not bake ([atlasFactory] returns null) there is
/// never an atlas and the grid draws text.
final class EmojiGlyphAtlasHost extends ChangeNotifier {
  /// Creates a host that plans from [dataSource] and bakes on [frames].
  ///
  /// [devicePixelRatio] sizes the baked glyph (capped at the atlas maximum)
  /// and can change later. [pageRetention] is how long baked pages stay
  /// resident after the panel closes; [memoryPressure] (typically a
  /// `SystemMemoryPressure` the shell owns and disposes) releases them at once.
  /// The remaining arguments default to the system font, a new in-memory store
  /// per atlas (ignored with [persistence], which keeps the pages in its
  /// cache), a wall clock and the platform's atlas factory; tests replace
  /// them.
  EmojiGlyphAtlasHost({
    required EmojiDataSource dataSource,
    required BakeFrameSource frames,
    required double devicePixelRatio,
    Duration pageRetention = GlyphPageResidency.defaultRetention,
    Listenable? memoryPressure,
    GlyphRasteriser? rasteriser,
    GlyphPageStore Function() newStore = MemoryGlyphPageStore.new,
    GlyphAtlasPersistence? persistence,
    BakeClock? clock,
    GlyphBakeObserver? observer,
    GlyphAtlasFactory atlasFactory = createGlyphAtlasForPlatform,
  }) : _persistence = persistence,
       _dataSource = dataSource,
       _frames = frames,
       _devicePixelRatio = devicePixelRatio,
       _pageRetention = pageRetention,
       _memoryPressure = memoryPressure,
       _rasteriser = rasteriser ?? ParagraphGlyphRasteriser(),
       _newStore = newStore,
       _clock = clock ?? _wallClock(),
       _observer = observer,
       _atlasFactory = atlasFactory;

  final EmojiDataSource _dataSource;
  final BakeFrameSource _frames;
  final Duration _pageRetention;
  final Listenable? _memoryPressure;
  final GlyphRasteriser _rasteriser;
  final GlyphPageStore Function() _newStore;
  final BakeClock _clock;
  final GlyphBakeObserver? _observer;
  final GlyphAtlasFactory _atlasFactory;

  /// Whether the panel is on screen. A hidden panel bakes nothing.
  final ValueNotifier<bool> panelVisible = ValueNotifier<bool>(false);

  /// Whether the panel is animating open or closed. Baking waits for it.
  final ValueNotifier<bool> panelOpening = ValueNotifier<bool>(false);

  double _devicePixelRatio;
  GlyphAtlasPersistence? _persistence;
  GlyphAtlas? _atlas;
  // The in-memory store of the current atlas (null with persistence); cleared
  // when that atlas is replaced.
  GlyphPageStore? _atlasStore;
  // What the grid last showed as recents, so a density change can plan again
  // without the shell.
  List<String> _recents = const <String>[];
  bool _disposed = false;

  /// The atlas to hand to the grid page, or null before the data is ready and
  /// on a platform that does not bake.
  GlyphAtlas? get atlas => _atlas;

  /// The density the baked glyphs are sized for.
  double get devicePixelRatio => _devicePixelRatio;

  /// Sizes the baked glyphs for a new screen density (the view moved to
  /// another display, or the display size changed). Plans again, behind the
  /// art already drawn, and re-keys the persistent cache: pages baked for
  /// another density are discarded when the new atlas reads it.
  set devicePixelRatio(double value) {
    if (value == _devicePixelRatio) return;
    _devicePixelRatio = value;
    _persistence = _persistence?.withDevicePixelRatio(value);
    if (_disposed || !_dataSource.isReady || _atlas == null) return;
    _plan(_planGlyphs(_recents));
  }

  /// Plans the atlas if the data is ready and the grid would draw a glyph the
  /// current one does not hold. [recents] are the glyphs of the recents
  /// section as the grid will show them.
  void sync({required Iterable<String> recents}) {
    if (_disposed || !_dataSource.isReady) return;
    _recents = List<String>.of(recents);
    final glyphs = _planGlyphs(_recents);
    final current = _atlas;
    if (current != null &&
        glyphs.every((glyph) => current.index.placementOf(glyph) != null)) {
      return;
    }
    _plan(glyphs);
  }

  /// Builds an atlas for [glyphs] and puts it in place of the current one.
  void _plan(List<String> glyphs) {
    final current = _atlas;
    final replacedStore = _atlasStore;
    final predecessor = current?.retire();
    if (replacedStore != null && predecessor != null) {
      // The retired atlas may still be writing its last page.
      unawaited(predecessor.settled.then((_) => replacedStore.clear()));
    }
    final residency = GlyphPageResidency(
      retention: _pageRetention,
      memoryPressure: _memoryPressure,
    );
    final store = _persistence == null ? _newStore() : null;
    // The layout depends on the display only; the glyph box is nominal (the
    // grid scales the sprite to its real cell).
    final atlas = _atlasFactory(
      GlyphAtlasRequest(
        index: GlyphAtlasIndex(
          glyphs,
          layout: GlyphAtlasLayout.forCell(
            logicalExtent: EmojiPage.cellPitch * kCatalogGlyphBoxFraction,
            devicePixelRatio: _devicePixelRatio,
          ),
        ),
        rasteriser: _rasteriser,
        store: store,
        persistence: _persistence,
        frames: _frames,
        clock: _clock,
        panelVisible: panelVisible,
        panelOpening: panelOpening,
        residency: residency,
        observer: _observer,
        predecessor: predecessor,
      ),
    );
    if (atlas == null) {
      // Nothing took them over (a platform that does not bake).
      residency.dispose();
      predecessor?.dispose();
      unawaited(store?.clear());
    }
    _atlasStore = atlas == null ? null : store;
    _atlas = atlas?..start();
    if (current != null || atlas != null) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _atlas?.dispose();
    _atlas = null;
    panelVisible.dispose();
    panelOpening.dispose();
    // Memory pages die with the host; persisted pages are kept on purpose.
    unawaited(_atlasStore?.clear());
    _atlasStore = null;
    super.dispose();
  }

  /// The catalogue as drawn, in the data layer's order, then the recents it
  /// does not hold.
  List<String> _planGlyphs(Iterable<String> recents) {
    final catalogue = <String>[
      for (final category in _dataSource.categories)
        for (final item in category.items)
          if (item case UnicodeEmojiItem(:final glyph, :final supportsSkinTone))
            supportsSkinTone
                ? EmojiSkinTone.apply(glyph, _dataSource.skinToneFor(glyph))
                : glyph,
    ];
    final known = catalogue.toSet();
    final extras = <String>{
      for (final glyph in recents)
        if (!known.contains(glyph)) glyph,
    }.toList()..sort();
    return [...catalogue, ...extras];
  }

  static BakeClock _wallClock() {
    final watch = Stopwatch()..start();
    return () => watch.elapsed;
  }
}
