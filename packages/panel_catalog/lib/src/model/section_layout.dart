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
  const factory SectionLayout.grid({
    int? spanCount,
    double? cellExtent,
    double? cellAspect,
    double? headerExtent,
    EdgeInsets insets,
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
    this.headerExtent,
    this.insets = EdgeInsets.zero,
  }) : assert(spanCount == null || spanCount >= 1, 'A grid needs a column.'),
       assert(
         cellExtent == null || cellAspect == null,
         'A grid sizes its cells by an extent or an aspect, not both.',
       ),
       assert(
         cellAspect == null || cellAspect > 0,
         'A cell aspect must be positive.',
       ),
       super._();

  /// Columns, or null for the viewport default.
  final int? spanCount;

  /// Fixed row height in content coordinates, or null for the viewport
  /// default (unless [cellAspect] is set).
  final double? cellExtent;

  /// Cell width / height. The row height is the cell width divided by it.
  final double? cellAspect;

  /// Header band height, or null for the viewport default.
  final double? headerExtent;

  /// Space the section keeps inside the viewport padding.
  ///
  /// Left and right narrow the section's usable width (so its columns and
  /// header text); top is empty space above the header and bottom below the
  /// last row. The header band itself never includes them.
  final EdgeInsets insets;

  @override
  bool operator ==(Object other) =>
      other is SectionLayout$Grid &&
      other.spanCount == spanCount &&
      other.cellExtent == cellExtent &&
      other.cellAspect == cellAspect &&
      other.headerExtent == headerExtent &&
      other.insets == insets;

  @override
  int get hashCode =>
      Object.hash(spanCount, cellExtent, cellAspect, headerExtent, insets);

  @override
  String toString() =>
      'SectionLayout.grid(span: $spanCount, cell: $cellExtent, '
      'aspect: $cellAspect, header: $headerExtent)';
}
