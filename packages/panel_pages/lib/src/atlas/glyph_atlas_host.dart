import 'dart:async';

import 'package:catalog_assets/glyph_atlas.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/foundation.dart';
import 'package:panel_pages/src/atlas/glyph_plan.dart';

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
/// [sync] takes a [GlyphPlan] and plans an atlas for it, because an atlas can
/// only draw glyphs it planned and the viewport never falls back to text where
/// glyphs are baked. When a glyph appears that the current atlas does not hold
/// (a variant chosen for the first time, a recent the catalogue lacks) or the
/// density changes ([devicePixelRatio]), the atlas is planned again and [atlas]
/// signals. The new atlas takes over what the old one was drawing
/// ([GlyphAtlas.retire]), so the grid never goes blank: it shows the old art
/// for the glyphs both plans hold while the new pages bake, and swaps once.
/// The old atlas stops before the new one touches the cache, so a persistent
/// cache always has one writer.
///
/// A plan whose glyphs are all held already changes nothing: a glyph that
/// left the plan (an emoji the device turned out not to draw) keeps its cell,
/// because planning without it would change the cache key and re-bake every
/// page.
///
/// ## Pause signals
///
/// The atlas bakes only while the panel is [visible] and not [opening]; the
/// host mirrors the two observables it is given (published by the shell,
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
final class GlyphAtlasHost {
  /// Creates a host that bakes on [frames], sized for glyphs drawn in a box
  /// [glyphBoxExtent] logical pixels wide.
  ///
  /// [glyphBoxExtent] is the largest box any section draws a glyph in
  /// (`catalogGlyphBoxExtent` of the cell), because there is **one** baked
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
    required ValueObservable<bool> visible,
    required ValueObservable<bool> opening,
    Duration pageRetention = GlyphPageResidency.defaultRetention,
    Listenable? memoryPressure,
    GlyphRasteriser? rasteriser,
    GlyphPageStore Function() newStore = MemoryGlyphPageStore.new,
    GlyphAtlasPersistence? persistence,
    BakeClock? clock,
    GlyphBakeObserver? observer,
    GlyphAtlasFactory atlasFactory = createGlyphAtlasForPlatform,
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
  final ValueObservable<bool> _visibleSource;
  final ValueObservable<bool> _openingSource;
  final Duration _pageRetention;
  final Listenable? _memoryPressure;
  final GlyphRasteriser _rasteriser;
  final GlyphPageStore Function() _newStore;
  final BakeClock _clock;
  final GlyphBakeObserver? _observer;
  final GlyphAtlasFactory _atlasFactory;
  final ValueNotifier<bool> _visible;
  final ValueNotifier<bool> _opening;
  final _atlas = ObservableValue<GlyphAtlas?>(null);

  double _devicePixelRatio;
  GlyphAtlasPersistence? _persistence;
  // The in-memory store of the current atlas (null with persistence); cleared
  // when that atlas is replaced.
  GlyphPageStore? _atlasStore;
  // The last plan given, so a density change can plan again without the page.
  GlyphPlan? _plan;
  // The factory said once that this platform bakes nothing; it will not change
  // its mind, so later plans do not ask again.
  bool _platformBakesNothing = false;
  bool _disposed = false;

  /// The atlas to draw from, or null before there is a plan and on a platform
  /// that does not bake. Signals when it is replaced.
  ValueObservable<GlyphAtlas?> get atlas => _atlas;

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
    final plan = _plan;
    if (_disposed || plan == null || _atlas.value == null) return;
    _replan(plan);
  }

  /// Plans the atlas for [plan] if the page would draw a glyph the current one
  /// does not hold.
  void sync(GlyphPlan plan) {
    if (_disposed || _platformBakesNothing) return;
    final current = _atlas.value;
    if (current != null &&
        plan.glyphs.every(
          (glyph) => current.index.placementOf(glyph) != null,
        )) {
      return;
    }
    _plan = plan;
    _replan(plan);
  }

  /// Builds an atlas for [plan] and puts it in place of the current one.
  void _replan(GlyphPlan plan) {
    final current = _atlas.value;
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
    // page scales the sprite to its real cell).
    final atlas = _atlasFactory(
      GlyphAtlasRequest(
        index: GlyphAtlasIndex(
          plan.glyphs,
          layout: GlyphAtlasLayout.forCell(
            logicalExtent: _glyphBoxExtent,
            devicePixelRatio: _devicePixelRatio,
          ),
        ),
        rasteriser: _rasteriser,
        store: store,
        persistence: _persistence,
        frames: _frames,
        clock: _clock,
        panelVisible: _visible,
        panelOpening: _opening,
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
      _platformBakesNothing = true;
    }
    _atlasStore = atlas == null ? null : store;
    _atlas.value = atlas?..start();
  }

  void _onVisible() => _visible.value = _visibleSource.value;

  void _onOpening() => _opening.value = _openingSource.value;

  /// Releases the atlas and stops following the panel's presence. Idempotent.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _visibleSource.removeListener(_onVisible);
    _openingSource.removeListener(_onOpening);
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
