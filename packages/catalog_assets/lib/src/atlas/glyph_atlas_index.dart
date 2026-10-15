import 'dart:ui';

import 'package:catalog_assets/src/atlas/glyph_atlas_layout.dart';
import 'package:meta/meta.dart';

/// Where one baked glyph lives: an atlas page and the rectangle of its pixels
/// on that page (gutter excluded), in page pixels.
@immutable
final class GlyphSprite {
  /// Creates a sprite on page [pageIndex] cut from [source].
  const GlyphSprite({required this.pageIndex, required this.source});

  /// Page the glyph is baked on.
  final int pageIndex;

  /// Source rectangle on the page, in page pixels.
  final Rect source;

  @override
  bool operator ==(Object other) =>
      other is GlyphSprite &&
      other.pageIndex == pageIndex &&
      other.source == source;

  @override
  int get hashCode => Object.hash(pageIndex, source);

  @override
  String toString() => 'GlyphSprite(page: $pageIndex, source: $source)';
}

/// The fixed plan of a catalogue: which page and cell every glyph is baked
/// into, decided once from the glyph list and never changed.
///
/// Placement depends only on the order of the glyphs the data layer supplies,
/// so it is the same before a glyph is baked and after, and a persisted page
/// can be matched to its glyphs again. Pure data: no pixels, no `dart:ui`
/// objects beyond [Rect].
///
/// A glyph listed twice occupies one cell (first occurrence wins).
final class GlyphAtlasIndex {
  /// Plans [glyphs] onto pages of [layout].
  GlyphAtlasIndex(
    Iterable<String> glyphs, {
    this.layout = const GlyphAtlasLayout(),
  }) : _glyphs = List<String>.unmodifiable(<String>{...glyphs}) {
    for (var i = 0; i < _glyphs.length; i++) {
      _slotOf[_glyphs[i]] = i;
    }
  }

  /// The page geometry this plan was made with.
  final GlyphAtlasLayout layout;

  final List<String> _glyphs;
  final Map<String, int> _slotOf = <String, int>{};

  /// Distinct glyphs in the plan.
  int get glyphCount => _glyphs.length;

  /// Pages the plan needs.
  int get pageCount => layout.pageCountFor(_glyphs.length);

  /// Planned sprite of [glyph], or null when it is not in the catalogue.
  ///
  /// Says where the glyph will be, not that it has been baked yet.
  GlyphSprite? placementOf(String glyph) {
    final position = _slotOf[glyph];
    if (position == null) return null;
    return GlyphSprite(
      pageIndex: position ~/ layout.cellsPerPage,
      source: layout.glyphRect(position % layout.cellsPerPage),
    );
  }

  /// Glyphs of page [pageIndex] in cell order.
  List<String> glyphsOnPage(int pageIndex) {
    assert(
      pageIndex >= 0 && pageIndex < pageCount,
      'page $pageIndex is outside 0..${pageCount - 1}',
    );
    final start = pageIndex * layout.cellsPerPage;
    final end = start + layout.cellsPerPage;
    return _glyphs.sublist(start, end > _glyphs.length ? _glyphs.length : end);
  }
}
