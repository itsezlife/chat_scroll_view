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
/// Pages bake in index order; a page is composed only when all its glyphs are
/// in strips, and a glyph has a [spriteOf] only once its page is stored. It
/// runs on the root isolate, because picture and text APIs are not available
/// in spawned isolates. The baker decides nothing about *when* to run:
/// pacing, priority and pausing are the caller's.
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
  int _bakedPages = 0;
  bool _stepping = false;
  bool _disposed = false;

  GlyphAtlasLayout get _layout => index.layout;

  /// Whether every page is composed and stored.
  bool get isComplete => _bakedPages >= index.pageCount;

  /// Whether page [pageIndex] is composed and stored.
  bool isPageBaked(int pageIndex) => pageIndex < _bakedPages;

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
      final page = _bakedPages;
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
    _bakedPages++;
  }

  void _dropStrips() {
    for (final strip in _strips) {
      strip.dispose();
    }
    _strips.clear();
    _stripGlyphCounts.clear();
    _stripped = 0;
  }
}
