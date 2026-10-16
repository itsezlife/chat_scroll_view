import 'package:flutter/painting.dart';
import 'package:meta/meta.dart';

/// How one [CatalogSection] lays out its leaves.
///
/// Geometry belongs to the section, not to the viewport: emoji groups, sticker
/// sets and GIF rows differ in column count and cell shape, and each is
/// projected with its own. The viewport-wide `spanCount`, `cellExtent` and
/// `headerExtent` are the **defaults** a section inherits wherever its layout
/// leaves a value unset (or has no layout at all).
///
/// ## Direction
///
/// A grid fills its cells **start to end**: the first leaf is in the column at
/// the start edge of the reading direction, so a right-to-left grid begins at
/// the right. [SectionLayout$Grid.textDirection] states the section's
/// direction; left unset it follows the viewport, which follows the
/// `Directionality` it sits in. Only the x of a cell changes with direction:
/// rows, extents, landing offsets and the order of leaves are the same, and
/// content (a glyph, a sticker, a GIF) is never mirrored.
///
/// The family is sealed so further kinds, for example justified rows for GIFs,
/// can join [SectionLayout$Grid] without a viewport-wide switch on a flag.
@immutable
sealed class SectionLayout {
  /// A grid of equal cells filled row by row.
  ///
  /// Every argument left null is inherited from the viewport defaults;
  /// [insets] default to none.
  ///
  /// [cellExtent] is a fixed row height. [cellAspect] is the cell's
  /// width / height and makes the row height follow the cell width instead, so
  /// the two are exclusive. [spanCount] must be at least 1.
  ///
  /// [desiredCellWidth] takes the columns from the width instead of
  /// [spanCount]: as many as fit at least that wide. [cellHeightInset] makes
  /// the row that much shorter than the cell is wide. Together they are the
  /// reference desktop client's emoji list (37 and 2).
  ///
  /// [glyphExtent] fixes the side of the glyph box instead of taking a
  /// fraction of the cell: an emoji is drawn that size, centred, whatever the
  /// width gives the cell, as the reference desktop client draws its emoji
  /// list.
  const factory SectionLayout.grid({
    int? spanCount,
    double? cellExtent,
    double? cellAspect,
    double? desiredCellWidth,
    double? cellHeightInset,
    double? glyphExtent,
    double? headerExtent,
    EdgeInsets insets,
    TextDirection? textDirection,
  }) = SectionLayout$Grid;

  const SectionLayout._();
}

/// A grid layout; see [SectionLayout.grid].
final class SectionLayout$Grid extends SectionLayout {
  /// Creates a grid layout. See [SectionLayout.grid].
  const SectionLayout$Grid({
    this.spanCount,
    this.cellExtent,
    this.cellAspect,
    this.desiredCellWidth,
    this.cellHeightInset,
    this.glyphExtent,
    this.headerExtent,
    this.insets = EdgeInsets.zero,
    this.textDirection,
  }) : assert(spanCount == null || spanCount >= 1, 'A grid needs a column.'),
       assert(
         cellExtent == null || cellAspect == null,
         'A grid sizes its cells by an extent or an aspect, not both.',
       ),
       assert(
         cellAspect == null || cellAspect > 0,
         'A cell aspect must be positive.',
       ),
       assert(
         desiredCellWidth == null || desiredCellWidth > 0,
         'A desired cell width must be positive.',
       ),
       assert(
         desiredCellWidth == null || spanCount == null,
         'A grid takes its columns from a count or from a width, not both.',
       ),
       assert(
         glyphExtent == null || glyphExtent > 0,
         'A glyph extent must be positive.',
       ),
       assert(
         cellHeightInset == null || (cellExtent == null && cellAspect == null),
         'A row is a fixed extent, an aspect of the cell or the cell width '
         'less an inset: one of them.',
       ),
       super._();

  /// Columns, or null for the viewport default.
  final int? spanCount;

  /// Fixed row height in content coordinates, or null for the viewport
  /// default (unless [cellAspect] is set).
  final double? cellExtent;

  /// Cell width / height. The row height is the cell width divided by it.
  final double? cellAspect;

  /// The narrowest a column may be, or null to use [spanCount]: the grid has
  /// as many columns as fit at this width (at least one), each a whole number
  /// of logical pixels wide, and what the division leaves is split on both
  /// sides, the smaller half at the start.
  final double? desiredCellWidth;

  /// How much shorter than the cell is wide a row is, or null for
  /// [cellExtent] / [cellAspect].
  final double? cellHeightInset;

  /// The side of the box a glyph is drawn in, or null for
  /// `CatalogContentBox.glyphBoxFraction` of the cell's shorter side. Held to
  /// the cell's shorter side. Content that fills its cell (a sticker) ignores
  /// it.
  final double? glyphExtent;

  /// Header band height, or null for the viewport default.
  final double? headerExtent;

  /// Space the section keeps inside the viewport padding.
  ///
  /// Left and right narrow the section's usable width (so its columns and
  /// header text); top is empty space above the header and bottom below the
  /// last row. The header band itself never includes them.
  final EdgeInsets insets;

  /// The direction cells fill in and the header reads in, or null for the
  /// viewport's (the `Directionality` it sits in).
  ///
  /// [insets] are physical: `left` stays on the left in either direction.
  final TextDirection? textDirection;

  @override
  bool operator ==(Object other) =>
      other is SectionLayout$Grid &&
      other.spanCount == spanCount &&
      other.cellExtent == cellExtent &&
      other.cellAspect == cellAspect &&
      other.desiredCellWidth == desiredCellWidth &&
      other.cellHeightInset == cellHeightInset &&
      other.glyphExtent == glyphExtent &&
      other.headerExtent == headerExtent &&
      other.insets == insets &&
      other.textDirection == textDirection;

  @override
  int get hashCode => Object.hash(
    spanCount,
    cellExtent,
    cellAspect,
    desiredCellWidth,
    cellHeightInset,
    glyphExtent,
    headerExtent,
    insets,
    textDirection,
  );

  @override
  String toString() =>
      'SectionLayout.grid(span: $spanCount, cell: $cellExtent, '
      'aspect: $cellAspect, desired: $desiredCellWidth, '
      'inset: $cellHeightInset, glyph: $glyphExtent, header: $headerExtent, '
      'direction: $textDirection)';
}
