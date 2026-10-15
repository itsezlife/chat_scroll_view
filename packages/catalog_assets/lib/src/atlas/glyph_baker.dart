import 'dart:math' as math;
import 'dart:ui';

import 'package:catalog_assets/src/atlas/glyph_atlas_index.dart';
import 'package:catalog_assets/src/atlas/glyph_atlas_layout.dart';
import 'package:catalog_assets/src/atlas/glyph_page_store.dart';
import 'package:catalog_assets/src/atlas/glyph_rasteriser.dart';

/// What one [GlyphBaker.step] did.
enum BakeStep {
  /// Rasterised a few glyphs into one strip image.
  strip,

  /// Composed the strips of one page into a page image and stored it.
  page,

  /// Nothing left to bake.
  done,
}

/// Bakes the glyphs of a [GlyphAtlasIndex] into atlas pages, a bounded amount
/// of work per call, so a caller can pace it across frames.
///
/// Work comes in two units, each sized to fit inside one frame:
///
/// - a **strip**: at most `glyphs` glyphs rasterised into one small image;
/// - a **page**: the strips of one page composed into a 2048 px page image and
///   handed to the [GlyphPageStore].
///
/// Pages bake in index order unless [prioritise] says which glyphs the user
/// is looking at. A page is composed only when all its glyphs are in strips,
/// and a glyph has a [spriteOf] only once its page is stored, so priority
/// works at page granularity: where a glyph sits is fixed by catalogue order
/// (a persisted page must match its glyphs again), and a visible glyph waits
/// for at most the page it is on, never for the rest of the catalogue. It
/// runs on the root isolate, because picture and text APIs are not available
/// in spawned isolates. The baker decides nothing about *when* to run:
/// pacing and pausing are the caller's (see `GlyphBakeScheduler`).
///
/// The baker never detects missing glyphs and never falls back to a
/// paragraph; it bakes exactly what the index lists.
final class GlyphBaker {
  /// Creates a baker for [index] that rasterises with [rasteriser] and keeps
  /// the composed pages in [store].
  GlyphBaker({
    required this.index,
    required GlyphRasteriser rasteriser,
    required GlyphPageStore store,
  }) : _rasteriser = rasteriser,
       _store = store;

  /// The plan being baked.
  final GlyphAtlasIndex index;

  final GlyphRasteriser _rasteriser;
  final GlyphPageStore _store;

  // Strips of the page being baked, in slot order, and how many of its glyphs
  // they hold. Dropped as soon as the page is composed.
  final List<Image> _strips = <Image>[];
  final List<int> _stripGlyphCounts = <int>[];
  int _stripped = 0;
  // The page whose strips are in [_strips], or null between pages.
  int? _current;
  final Set<int> _baked = <int>{};
  // Pages holding the prioritised glyphs, in the order they were listed.
  List<int> _wanted = const <int>[];
  int? _lastBakedPage;
  bool _stepping = false;
  bool _disposed = false;

  GlyphAtlasLayout get _layout => index.layout;

  /// Whether every page is composed and stored.
  bool get isComplete => _baked.length >= index.pageCount;

  /// Whether page [pageIndex] is composed and stored.
  bool isPageBaked(int pageIndex) => _baked.contains(pageIndex);

  /// The page the latest [BakeStep.page] composed, or null before the first.
  int? get lastBakedPage => _lastBakedPage;

  /// Records that page [pageIndex] already exists in the store (restored from
  /// a persisted set), so it is not baked again and its glyphs have a
  /// [spriteOf]. Call it before baking starts.
  void markBaked(int pageIndex) {
    assert(
      pageIndex >= 0 && pageIndex < index.pageCount,
      'page $pageIndex is outside 0..${index.pageCount - 1}',
    );
    assert(!_stepping && _current != pageIndex, 'the page is being baked');
    _baked.add(pageIndex);
  }

  /// Says which glyphs the user is looking at, most important first; their
  /// pages bake before the others, then the pages nearest to them.
  ///
  /// A page in progress that holds none of them is left for later: its strips
  /// are dropped and it bakes again from scratch, because making a visible
  /// glyph wait for a whole page of unseen work is worse than redoing some of
  /// it. A page in progress that holds one is finished, never restarted.
  /// Glyphs outside the catalogue are ignored; an empty list restores
  /// catalogue order. Cheap: nothing is baked until the next [step].
  void prioritise(Iterable<String> glyphs) {
    final pages = <int>[];
    for (final glyph in glyphs) {
      final page = index.placementOf(glyph)?.pageIndex;
      if (page != null && !pages.contains(page)) pages.add(page);
    }
    _wanted = pages;
  }

  /// Sprite of [glyph], or null when it is unknown or its page is not baked
  /// yet (the caller shows a placeholder until then).
  GlyphSprite? spriteOf(String glyph) {
    final planned = index.placementOf(glyph);
    return planned != null && isPageBaked(planned.pageIndex) ? planned : null;
  }

  /// Does one unit of work: a strip of up to [glyphs] glyphs, or the page
  /// composition once its glyphs are all stripped.
  Future<BakeStep> step({required int glyphs}) async {
    assert(!_disposed, 'step() after dispose()');
    assert(glyphs > 0, 'a step must bake at least one glyph');
    assert(!_stepping, 'step() called while the previous step is running');
    if (isComplete) return BakeStep.done;
    _stepping = true;
    try {
      final page = _pageToBake();
      final onPage = index.glyphsOnPage(page);
      if (_stripped < onPage.length) {
        _bakeStrip(onPage, glyphs);
        return BakeStep.strip;
      }
      await _composePage(page, onPage);
      return BakeStep.page;
    } finally {
      _stepping = false;
    }
  }

  /// Bakes everything: one [step] per frame, waiting for [nextFrame] before
  /// each. A fixed pace; adaptive pacing is the caller's to build on [step].
  Future<void> bakeAll({
    required int glyphsPerFrame,
    required Future<void> Function() nextFrame,
  }) async {
    while (!isComplete && !_disposed) {
      await nextFrame();
      await step(glyphs: glyphsPerFrame);
    }
  }

  /// Releases the images of a bake in progress. Stored pages stay in the store.
  void dispose() {
    _disposed = true;
    _dropStrips();
  }

  /// The page this step works on: the one in progress while it is still
  /// wanted (or nothing wanted is left), else the best unbaked page.
  int _pageToBake() {
    final current = _current;
    final wanted = _wanted.where((p) => !isPageBaked(p));
    if (current != null) {
      if (wanted.isEmpty || _wanted.contains(current)) return current;
      _dropStrips();
    }
    return _current = wanted.isNotEmpty ? wanted.first : _nearestUnbaked();
  }

  /// The unbaked page nearest to a wanted one, lowest index first on a tie;
  /// with nothing wanted that is simply the lowest unbaked page.
  int _nearestUnbaked() {
    int distance(int page) => _wanted.isEmpty
        ? page
        : _wanted.map((w) => (w - page).abs()).reduce(math.min);
    int? best;
    for (var page = 0; page < index.pageCount; page++) {
      if (isPageBaked(page)) continue;
      if (best == null || distance(page) < distance(best)) best = page;
    }
    return best!;
  }

  void _bakeStrip(List<String> onPage, int budget) {
    final count = math.min(onPage.length - _stripped, budget);
    final cell = _layout.cellSize;
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    for (var i = 0; i < count; i++) {
      _rasteriser.paint(
        canvas,
        onPage[_stripped + i],
        Rect.fromLTWH(
          i * cell + GlyphAtlasLayout.gutter.toDouble(),
          GlyphAtlasLayout.gutter.toDouble(),
          _layout.glyphSize.toDouble(),
          _layout.glyphSize.toDouble(),
        ),
      );
    }
    final picture = recorder.endRecording();
    _strips.add(picture.toImageSync(count * cell, cell));
    picture.dispose();
    _stripGlyphCounts.add(count);
    _stripped += count;
  }

  Future<void> _composePage(int page, List<String> onPage) async {
    final cell = _layout.cellSize.toDouble();
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    // A 1:1 copy: no smoothing, or the transparent gutter would bleed.
    final copy = Paint()
      ..filterQuality = FilterQuality.none
      ..isAntiAlias = false;
    var slot = 0;
    for (var s = 0; s < _strips.length; s++) {
      for (var k = 0; k < _stripGlyphCounts[s]; k++, slot++) {
        canvas.drawImageRect(
          _strips[s],
          Rect.fromLTWH(k * cell, 0, cell, cell),
          _layout.cellOrigin(slot) & Size.square(cell),
          copy,
        );
      }
    }
    final picture = recorder.endRecording();
    final image = picture.toImageSync(
      GlyphAtlasLayout.pageSize,
      GlyphAtlasLayout.pageSize,
    );
    picture.dispose();
    _dropStrips();
    try {
      await _store.write(page, image);
    } finally {
      image.dispose();
    }
    _baked.add(page);
    _lastBakedPage = page;
    _current = null;
  }

  void _dropStrips() {
    for (final strip in _strips) {
      strip.dispose();
    }
    _strips.clear();
    _stripGlyphCounts.clear();
    _stripped = 0;
    _current = null;
  }
}
