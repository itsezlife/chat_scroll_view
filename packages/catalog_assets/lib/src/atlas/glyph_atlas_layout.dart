import 'dart:math' as math;
import 'dart:ui';

import 'package:meta/meta.dart';

/// Geometry of a **glyph atlas page**: how many baked glyph cells fit on one
/// fixed-size page and where each cell sits.
///
/// The three numbers that decide memory and sharpness are single constants:
///
/// - [pageSize], 2048 px, the only texture size guaranteed on every GPU;
/// - [maxGlyphSize], 72 px, the cap on the baked glyph edge. At the reference
///   density a full-size bake would be 98 px and five pages (about 80 MiB),
///   past the 64 MiB ceiling, so the glyph is baked smaller and the sprite is
///   scaled up when drawn;
/// - [gutter], 2 px of transparent border around every glyph, so sampling a
///   sprite near its edge never picks up the neighbouring cell.
///
/// With the defaults a cell is 76 px, a page holds 26 x 26 = 676 cells, and
/// the current catalogue (about 1.6 thousand glyphs) needs three pages, 48 MiB
/// raw. Escalation when the cap fails a visual check on a device class is
/// windowed residency, not a higher cap or a bigger page.
@immutable
final class GlyphAtlasLayout {
  /// A layout baking glyphs [glyphSize] px wide, [maxGlyphSize] at most.
  const GlyphAtlasLayout({this.glyphSize = maxGlyphSize})
    : assert(glyphSize > 0, 'glyphSize must be positive'),
      assert(
        glyphSize <= maxGlyphSize,
        'glyphSize is capped at maxGlyphSize: a larger bake no longer fits '
        'the resident-memory ceiling (see GlyphAtlasLayout)',
      );

  /// Layout for a cell drawn [logicalExtent] logical px wide at
  /// [devicePixelRatio]: the exact physical size, capped at [maxGlyphSize].
  factory GlyphAtlasLayout.forCell({
    required double logicalExtent,
    required double devicePixelRatio,
  }) {
    final wanted = (logicalExtent * devicePixelRatio).ceil();
    return GlyphAtlasLayout(glyphSize: math.min(maxGlyphSize, wanted));
  }

  /// Page edge in px. Fixed: pages are 2048 by 2048.
  static const int pageSize = 2048;

  /// Largest baked glyph edge in px.
  static const int maxGlyphSize = 72;

  /// Transparent border around each glyph in px, on every side.
  static const int gutter = 2;

  /// Bytes per pixel of a page (RGBA8888).
  static const int bytesPerPixel = 4;

  /// Baked glyph edge in px.
  final int glyphSize;

  /// Cell edge in px: the glyph plus a [gutter] on each side.
  int get cellSize => glyphSize + 2 * gutter;

  /// Cells per page row (and per page column).
  int get columns => pageSize ~/ cellSize;

  /// Cells on one page.
  int get cellsPerPage => columns * columns;

  /// Raw bytes of one page (mip levels excluded).
  int get pageBytes => pageSize * pageSize * bytesPerPixel;

  /// Pages needed for [glyphCount] glyphs.
  int pageCountFor(int glyphCount) => (glyphCount / cellsPerPage).ceil();

  /// Raw resident bytes of the pages [glyphCount] glyphs need.
  int residentBytesFor(int glyphCount) => pageCountFor(glyphCount) * pageBytes;

  /// Top-left corner of the whole cell (gutter included) in slot [slot] of a
  /// page; slots run left to right, then top to bottom.
  Offset cellOrigin(int slot) {
    assert(
      slot >= 0 && slot < cellsPerPage,
      'slot $slot is outside 0..${cellsPerPage - 1}',
    );
    return Offset(
      (slot % columns) * cellSize.toDouble(),
      (slot ~/ columns) * cellSize.toDouble(),
    );
  }

  /// The glyph's pixels in slot [slot] of a page: the cell without its gutter.
  Rect glyphRect(int slot) =>
      cellOrigin(slot).translate(gutter.toDouble(), gutter.toDouble()) &
      Size.square(glyphSize.toDouble());

  @override
  bool operator ==(Object other) =>
      other is GlyphAtlasLayout && other.glyphSize == glyphSize;

  @override
  int get hashCode => glyphSize.hashCode;

  @override
  String toString() => 'GlyphAtlasLayout(glyphSize: $glyphSize)';
}
