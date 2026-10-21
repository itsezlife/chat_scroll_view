import 'dart:async';

import 'package:catalog_assets/catalog_assets.dart'
    show GlyphSpriteSource, LayeredGlyphSource;
import 'package:catalog_assets/glyph_atlas.dart';
import 'package:flutter/foundation.dart';
import 'package:listen/listen.dart' as listen;
import 'package:panel_pages/src/atlas/glyph_plan.dart';
import 'package:panel_pages/src/bake/bake_activity_port.dart';

/// Builds the atlas a [GlyphAtlasRequest] describes; the web counterpart
/// returns null.
typedef GlyphAtlasFactory = GlyphAtlas? Function(GlyphAtlasRequest request);

/// Owns the [GlyphAtlas] of a page for as long as the page's shell lives, so
/// closing and reopening the panel does not bake again.
///
/// A page widget is torn down every time the panel closes; the baked pages
/// must not be. This host sits above it (the page keeps it in its controller):
/// it is told what to plan ([sync]) and when the panel is visible and opening,
/// and gives the page its [atlas].
///
/// ## What is planned
///
/// The first [sync] plans the [atlas] for its [GlyphPlan], baked in the
/// background. A later plan with glyphs no atlas holds (a variant chosen for
/// the first time, a recent the catalogue lacks) does not plan that atlas
/// again: an atlas for just those glyphs joins as a layer of [source], and
/// bakes them in a page or two. Nothing already baked is baked again, and the
/// persisted pages keep their key. Until a layer has baked a glyph, [source]
/// does not make a surface wait for it ([GlyphSpriteSource.waitsForSprite]):
/// the glyph is drawn as text for those frames, never as a placeholder.
///
/// No glyph ever leaves [source]: a plan without one (the user chose another
/// tone) still has surfaces outside the panel drawing it, such as the inline
/// emoji of a composer. Only a density change ([devicePixelRatio]) plans the
/// [atlas] again, for every glyph of every layer; the layers go, and the new
/// atlas takes over what the old one was drawing ([GlyphAtlas.retire]) so the
/// grid never goes blank. The old atlas stops before the new one touches the
/// cache, so a persistent cache always has one writer.
///
/// ## Pause signals
///
/// The atlas bakes only while the panel is [visible] and not [opening]; the
/// host mirrors the two listenables it is given (published by the shell,
/// which has them from the presentation) into the notifiers the atlas takes.
///
/// ## The glyph-support probe
///
/// An [observer] is shown every glyph the bake draws, so which glyphs the
/// system cannot draw is learned in the same pass that bakes them. The atlas
/// still plans whatever it is given, filtered or not; filtering the plan
/// would make the cache key depend on the probe's result.
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
/// Each atlas gets a [GlyphPageResidency] that holds the pages while the panel
/// is open and for `pageRetention` after it closes (60 seconds unless the
/// host says otherwise), and releases them at once when `memoryPressure`
/// fires. Reopening within the retention needs no reload; after it, or after
/// pressure, the pages are read back from the store. With the default
/// in-memory store the texture stays alive behind the store's own handle, so
/// release frees the handles but not the bytes; a store that persists pages
/// off the heap (the disk cache) is what returns the memory.
///
/// On a platform that does not bake ([atlasFactory] returns null) there is
/// never an atlas and the page draws text.
///
/// ## Activity
///
/// The host is the [BakeActivityPort] of its page: motion and the glyphs on
/// screen reach every layer, including one added while the motion lasts.
final class GlyphAtlasHost implements BakeActivityPort {
  /// Creates a host that bakes on [frames], sized for glyphs drawn in a box
  /// [glyphBoxExtent] logical pixels wide.
  ///
  /// [glyphBoxExtent] is the largest box any section draws a glyph in
  /// (`CatalogContentBox.glyphBoxExtent` of the cell), because there is **one** baked
  /// size per atlas and every section scales it. [devicePixelRatio] sizes the
  /// baked glyph (capped at the atlas maximum) and can change later.
  /// [visible] and [opening] are the panel's presence. [pageRetention] is how
  /// long baked pages stay resident after the panel closes; [memoryPressure]
  /// (typically a `SystemMemoryPressure` the host owns and disposes) releases
  /// them at once. The remaining arguments default to the system font, a new
  /// in-memory store per atlas (ignored with [persistence], which keeps the
  /// pages in its cache), a wall clock and the platform's atlas factory; tests
  /// replace them.
  GlyphAtlasHost({
    required BakeFrameSource frames,
    required double devicePixelRatio,
    required double glyphBoxExtent,
    required listen.ValueListenable<bool> visible,
    required listen.ValueListenable<bool> opening,
    Duration pageRetention = GlyphPageResidency.defaultRetention,
    Listenable? memoryPressure,
    GlyphRasteriser? rasteriser,
    GlyphPageStore Function() newStore = MemoryGlyphPageStore.new,
    GlyphAtlasPersistence? persistence,
    BakeClock? clock,
    GlyphBakeObserver? observer,
    GlyphAtlasFactory atlasFactory = GlyphAtlas.forPlatform,
  }) : _frames = frames,
       _devicePixelRatio = devicePixelRatio,
       _glyphBoxExtent = glyphBoxExtent,
       _visibleSource = visible,
       _openingSource = opening,
       _pageRetention = pageRetention,
       _memoryPressure = memoryPressure,
       _rasteriser = rasteriser ?? ParagraphGlyphRasteriser(),
       _newStore = newStore,
       _persistence = persistence,
       _clock = clock ?? _wallClock(),
       _observer = observer,
       _atlasFactory = atlasFactory,
       _visible = ValueNotifier<bool>(visible.value),
       _opening = ValueNotifier<bool>(opening.value) {
    visible.addListener(_onVisible);
    opening.addListener(_onOpening);
  }

  final BakeFrameSource _frames;
  final double _glyphBoxExtent;
  final listen.ValueListenable<bool> _visibleSource;
  final listen.ValueListenable<bool> _openingSource;
  final Duration _pageRetention;
  final Listenable? _memoryPressure;
  final GlyphRasteriser _rasteriser;
  final GlyphPageStore Function() _newStore;
  final BakeClock _clock;
  final GlyphBakeObserver? _observer;
  final GlyphAtlasFactory _atlasFactory;
  final ValueNotifier<bool> _visible;
  final ValueNotifier<bool> _opening;
  final _atlas = listen.ValueNotifier<GlyphAtlas?>(null);
  final _source = listen.ValueNotifier<LayeredGlyphSource?>(null);
  // The atlases planned after [_atlas] for the glyphs it lacked, with the
  // in-memory store of each.
  final List<(GlyphAtlas, GlyphPageStore)> _layers = [];
  final Set<Object> _scrollers = {};
  List<String> _priority = const [];

  double _devicePixelRatio;
  GlyphAtlasPersistence? _persistence;
  // The in-memory store of the current atlas (null with persistence); cleared
  // when that atlas is replaced.
  GlyphPageStore? _atlasStore;
  // The factory said once that this platform bakes nothing; it will not change
  // its mind, so later plans do not ask again.
  bool _platformBakesNothing = false;
  bool _disposed = false;

  /// The atlas of the first plan, baked in the background, or null before
  /// there is a plan and on a platform that does not bake. Signals when it is
  /// replaced.
  listen.ValueListenable<GlyphAtlas?> get atlas => _atlas;

  /// What a surface draws from: [atlas], then the layers planned for the
  /// glyphs it lacked. Null exactly when [atlas] is; replaced (and signals)
  /// with it, not when a layer joins.
  listen.ValueListenable<GlyphSpriteSource?> get source => _source;

  /// Whether a plan found out that this platform bakes nothing, so no atlas
  /// will ever exist. False until the first plan is made.
  bool get bakesNothing => _platformBakesNothing;

  /// The density the baked glyphs are sized for.
  double get devicePixelRatio => _devicePixelRatio;

  /// Sizes the baked glyphs for a new screen density (the view moved to
  /// another display, or the display size changed). Plans again, behind the
  /// art already drawn, and re-keys the persistent cache: pages baked for
  /// another density are discarded when the new atlas reads it.
  ///
  /// Before there is an atlas it only remembers the density.
  set devicePixelRatio(double value) {
    if (value == _devicePixelRatio) return;
    _devicePixelRatio = value;
    _persistence = _persistence?.withDevicePixelRatio(value);
    final current = _atlas.value;
    if (_disposed || current == null) return;
    _replan(GlyphPlan([..._glyphs]));
  }

  /// Makes sure every glyph of [plan] is held: the first plan becomes the
  /// [atlas]; a later one adds a layer for the glyphs nothing holds yet.
  void sync(GlyphPlan plan) {
    if (_disposed || _platformBakesNothing) return;
    if (_atlas.value == null) {
      _replan(plan);
      return;
    }
    final held = _glyphs;
    final missing = [
      for (final glyph in plan.glyphs)
        if (!held.contains(glyph)) glyph,
    ];
    if (missing.isEmpty) return;
    _addLayer(missing);
  }

  @override
  void reportScrolling({required Object reporter, required bool scrolling}) {
    if (_disposed) return;
    if (scrolling) {
      _scrollers.add(reporter);
    } else {
      _scrollers.remove(reporter);
    }
    for (final atlas in _atlases) {
      atlas.reportScrolling(reporter: reporter, scrolling: scrolling);
    }
  }

  @override
  void prioritise(List<String> glyphs) {
    if (_disposed) return;
    _priority = glyphs;
    for (final atlas in _atlases) {
      atlas.prioritise(glyphs);
    }
  }

  Iterable<GlyphAtlas> get _atlases => [
    ?_atlas.value,
    for (final (atlas, _) in _layers) atlas,
  ];

  // Every glyph some atlas holds, in plan order.
  Set<String> get _glyphs => {
    for (final atlas in _atlases) ...atlas.index.glyphs,
  };

  /// Builds an atlas for [plan] and puts it in place of the current one and
  /// its layers.
  void _replan(GlyphPlan plan) {
    final current = _atlas.value;
    final replacedStore = _atlasStore;
    final predecessor = current?.retire();
    if (replacedStore != null && predecessor != null) {
      // The retired atlas may still be writing its last page.
      unawaited(predecessor.settled.then((_) => replacedStore.clear()));
    }
    _dropLayers();
    final store = switch (_persistence) {
      null => _newStore(),
      _ => null,
    };
    final atlas = _build(
      plan.glyphs,
      store: store,
      persistence: _persistence,
      predecessor: predecessor,
    );
    if (atlas == null) {
      // Nothing took them over (a platform that does not bake).
      predecessor?.dispose();
      unawaited(store?.clear());
      _platformBakesNothing = true;
    }
    _atlasStore = switch (atlas) {
      null => null,
      _ => store,
    };
    _atlas.value = atlas?..start();
    _source.value?.dispose();
    _source.value = switch (atlas) {
      final atlas? => LayeredGlyphSource(atlas),
      null => null,
    };
  }

  /// Plans an atlas of its own for [glyphs], in a store of its own (never the
  /// persistent cache, whose key is the first plan's), and adds it to
  /// [source].
  void _addLayer(List<String> glyphs) {
    final store = _newStore();
    final atlas = _build(glyphs, store: store);
    if (atlas == null) {
      unawaited(store.clear());
      return;
    }
    _layers.add((atlas, store));
    for (final reporter in _scrollers) {
      atlas.reportScrolling(reporter: reporter, scrolling: true);
    }
    if (_priority.isNotEmpty) atlas.prioritise(_priority);
    atlas.start();
    _source.value?.add(atlas);
  }

  GlyphAtlas? _build(
    List<String> glyphs, {
    required GlyphPageStore? store,
    GlyphAtlasPersistence? persistence,
    RetiredGlyphArt? predecessor,
  }) {
    final residency = GlyphPageResidency(
      retention: _pageRetention,
      memoryPressure: _memoryPressure,
    );
    // The layout depends on the display only; the glyph box is nominal (the
    // page scales the sprite to its real cell).
    final atlas = _atlasFactory(
      GlyphAtlasRequest(
        index: GlyphAtlasIndex(
          glyphs,
          layout: GlyphAtlasLayout.forCell(
            logicalExtent: _glyphBoxExtent,
            devicePixelRatio: _devicePixelRatio,
          ),
        ),
        rasteriser: _rasteriser,
        store: store,
        persistence: persistence,
        frames: _frames,
        clock: _clock,
        panelVisible: _visible,
        panelOpening: _opening,
        residency: residency,
        observer: _observer,
        predecessor: predecessor,
      ),
    );
    if (atlas == null) residency.dispose();
    return atlas;
  }

  void _dropLayers() {
    for (final (atlas, store) in _layers) {
      _source.value?.remove(atlas);
      final retired = atlas.retire()..dispose();
      unawaited(retired.settled.then((_) => store.clear()));
    }
    _layers.clear();
  }

  void _onVisible() => _visible.value = _visibleSource.value;

  void _onOpening() => _opening.value = _openingSource.value;

  /// Releases the atlas and stops following the panel's presence. Idempotent.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _visibleSource.removeListener(_onVisible);
    _openingSource.removeListener(_onOpening);
    _dropLayers();
    _source.value?.dispose();
    _source.value = null;
    _source.dispose();
    _atlas.value?.dispose();
    _atlas.value = null;
    _atlas.dispose();
    _visible.dispose();
    _opening.dispose();
    // Memory pages die with the host; persisted pages are kept on purpose.
    unawaited(_atlasStore?.clear());
    _atlasStore = null;
  }

  static BakeClock _wallClock() {
    final watch = Stopwatch()..start();
    return () => watch.elapsed;
  }
}
