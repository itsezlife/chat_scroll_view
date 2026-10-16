import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:panel_catalog/src/model/catalog_glyph_box.dart';
import 'package:panel_catalog/src/model/catalog_leaf.dart';
import 'package:panel_catalog/src/model/catalog_leaf_hit.dart';
import 'package:panel_catalog/src/model/catalog_section.dart';
import 'package:panel_catalog/src/model/catalog_section_action.dart';
import 'package:panel_catalog/src/model/catalog_section_state.dart';
import 'package:panel_catalog/src/viewport/catalog_grid_metrics.dart';

/// One laid-out band in the flattened catalog projection (content coordinates).
///
/// Content y increases downward from the catalog top (`0` after top padding).
/// Slots are pure geometry + identity — no asset readiness, no paint mode.
/// The render object translates by `−offset` at paint time so content-y
/// [top] aligns into the viewport.
///
/// Slots of every section share one list in ascending order of both [top] and
/// [bottom], whatever each section's layout is: a section's slots lie below the
/// previous section's, and the slots of a row share their vertical extent. That
/// order is what lets the visible window be found by binary search.
///
/// Use [CatalogLayoutSlot.header] / [CatalogLayoutSlot.leaf] /
/// [CatalogLayoutSlot.skeleton] / [CatalogLayoutSlot.message] factories.
sealed class CatalogLayoutSlot {
  /// Creates a slot spanning `[top, top + height)`.
  const CatalogLayoutSlot({required this.top, required this.height});

  /// Section title band (the section's usable width; title painted by the leaf
  /// painter).
  const factory CatalogLayoutSlot.header({
    required double top,
    required double height,
    required double left,
    required double width,
    required String title,
    required String sectionId,
    CatalogSectionAction? action,
    TextDirection textDirection,
  }) = CatalogHeaderSlot;

  /// Leaf cell at column [left] with [width] (the section's cell width).
  const factory CatalogLayoutSlot.leaf({
    required double top,
    required double height,
    required double left,
    required double width,
    required String sectionId,
    required int index,
    required CatalogLeaf leaf,
    CatalogContentBox? contentBox,
    CatalogPlaceholderStyle? placeholderStyle,
    double? glyphExtent,
  }) = CatalogLeafSlot;

  /// Skeleton cell of a section that is loading or failed: geometry and the
  /// style it stands in, no content and no identity.
  const factory CatalogLayoutSlot.skeleton({
    required double top,
    required double height,
    required double left,
    required double width,
    required CatalogContentBox contentBox,
    required CatalogPlaceholderStyle style,
    double? glyphExtent,
  }) = CatalogSkeletonSlot;

  /// The row of a loaded section with nothing in it: [text] across the
  /// section's usable width.
  const factory CatalogLayoutSlot.message({
    required double top,
    required double height,
    required double left,
    required double width,
    required String text,
  }) = CatalogMessageSlot;

  /// Content y of the slot top edge.
  final double top;

  /// Slot height in content coordinates.
  final double height;

  /// Content y of the slot bottom edge (`top + height`).
  double get bottom => top + height;
}

/// Section title band.
///
/// Emitted for every [CatalogSection], including those with an empty leaf
/// list — empty sections still reserve header extent for strip / jump landing.
final class CatalogHeaderSlot extends CatalogLayoutSlot {
  /// Creates a header slot at [top] with [height] and host-localized [title].
  const CatalogHeaderSlot({
    required super.top,
    required super.height,
    required this.left,
    required this.width,
    required this.title,
    required this.sectionId,
    this.action,
    this.textDirection = TextDirection.ltr,
  });

  /// Content x of the section's left edge (viewport padding plus the section's
  /// left inset).
  final double left;

  /// Width the section's header shares with its columns.
  final double width;

  /// Host-localized section title (viewport paints; does not own l10n).
  final String title;

  /// [CatalogSection.id] of the section this header belongs to.
  final String sectionId;

  /// The section's trailing action, if it has one.
  final CatalogSectionAction? action;

  /// The direction the title reads in: it starts at this side of the band and
  /// the action sits at the other.
  final TextDirection textDirection;
}

/// One skeleton cell: where a leaf will be while its section loads.
///
/// A skeleton is geometry plus the style it stands in. It has no content key,
/// attaches nothing to the asset cache, and is not a hit target.
final class CatalogSkeletonSlot extends CatalogLayoutSlot {
  /// Creates a skeleton cell.
  const CatalogSkeletonSlot({
    required super.top,
    required super.height,
    required this.left,
    required this.width,
    required this.contentBox,
    required this.style,
    this.glyphExtent,
  });

  /// Content x of the cell left edge.
  final double left;

  /// Cell width.
  final double width;

  /// The box the skeleton is drawn in.
  final CatalogContentBox contentBox;

  /// The stand-in drawn.
  final CatalogPlaceholderStyle style;

  /// The grid's fixed glyph box side, or null for the fraction of the cell.
  final double? glyphExtent;

  /// Side of the square the skeleton is drawn in.
  double get contentExtent => catalogContentBoxExtent(
    contentBox,
    width,
    height,
    glyphExtent: glyphExtent,
  );
}

/// The row that tells a loaded section has nothing to show.
final class CatalogMessageSlot extends CatalogLayoutSlot {
  /// Creates a message row.
  const CatalogMessageSlot({
    required super.top,
    required super.height,
    required this.left,
    required this.width,
    required this.text,
  });

  /// Content x of the section's left edge.
  final double left;

  /// The section's usable width.
  final double width;

  /// Host-localized message.
  final String text;
}

/// One leaf cell in the grid.
///
/// [left] / [width] are content-x; [top] / [height] are content-y. The cell is
/// identified by [sectionId] and [index]; [key] identifies where it was laid
/// out, which the press chrome uses.
final class CatalogLeafSlot extends CatalogLayoutSlot {
  /// Creates a leaf cell slot.
  const CatalogLeafSlot({
    required super.top,
    required super.height,
    required this.left,
    required this.width,
    required this.sectionId,
    required this.index,
    required this.leaf,
    CatalogContentBox? contentBox,
    CatalogPlaceholderStyle? placeholderStyle,
    this.glyphExtent,
  }) : _contentBox = contentBox,
       _placeholderStyle = placeholderStyle;

  /// Content x of the cell left edge (includes section padding.left).
  final double left;

  /// Cell width (`usableWidth / spanCount` of the section's grid when usable
  /// width > 0).
  final double width;

  /// [CatalogSection.id] of the section this cell belongs to.
  final String sectionId;

  /// Position of the cell in its section's leaves.
  final int index;

  /// Leaf projected into this cell (identity only).
  final CatalogLeaf leaf;

  final CatalogContentBox? _contentBox;
  final CatalogPlaceholderStyle? _placeholderStyle;

  /// The box this cell's content is asked for and drawn in: its section's
  /// override, else what the leaf's facts say.
  CatalogContentBox get contentBox => _contentBox ?? leaf.contentBox;

  /// The stand-in of this cell: its section's override, else what the leaf's
  /// facts say.
  CatalogPlaceholderStyle get placeholderStyle =>
      _placeholderStyle ?? leaf.placeholderStyle;

  /// The grid's fixed glyph box side, or null for the fraction of the cell.
  final double? glyphExtent;

  /// Side of the square the content is asked for and drawn in.
  double get contentExtent => catalogContentBoxExtent(
    contentBox,
    width,
    height,
    glyphExtent: glyphExtent,
  );

  /// The section override of [contentBox], to carry onto a copy of this slot.
  CatalogContentBox? get contentBoxOverride => _contentBox;

  /// The section override of [placeholderStyle], to carry onto a copy of this
  /// slot.
  CatalogPlaceholderStyle? get placeholderStyleOverride => _placeholderStyle;

  /// The interaction result for this cell.
  CatalogLeafHit get hit =>
      CatalogLeafHit(sectionId: sectionId, index: index, leaf: leaf);

  /// Stable cell identity for hit-test and press feedback within one project.
  CatalogLeafSlotKey get key => CatalogLeafSlotKey(top: top, left: left);
}

/// Content-space identity for one projected leaf cell.
///
/// Press scale / list-selector chrome key off this, not the leaf's content
/// key, so duplicate glyphs in different sections animate independently.
@immutable
final class CatalogLeafSlotKey {
  /// Creates a slot key at content [top] and [left].
  const CatalogLeafSlotKey({required this.top, required this.left});

  /// Content y of the cell top edge.
  final double top;

  /// Content x of the cell left edge.
  final double left;

  @override
  bool operator ==(Object other) =>
      other is CatalogLeafSlotKey && other.top == top && other.left == left;

  @override
  int get hashCode => Object.hash(top, left);
}

/// Where one section sits in content coordinates and how its rows are laid out.
///
/// The compact per-section shape of the projection: the section landing and
/// near / far gate math reads these, not the slots, so it costs O(sections) at
/// most whatever the leaf count.
final class CatalogSectionBand {
  /// Creates the band of the section starting at content [top].
  const CatalogSectionBand({
    required this.top,
    required this.grid,
    required this.rowCount,
    required this.flatIndex,
  });

  /// Content y where the band starts: the previous band's [bottom], or the
  /// viewport's top padding.
  final double top;

  /// The section's resolved grid.
  final CatalogGridMetrics grid;

  /// Leaf rows below the header.
  final int rowCount;

  /// Flat adapter index of the header: one index per header plus one per leaf
  /// row (not per cell), counted across all earlier sections.
  final int flatIndex;

  /// Content y of the header top edge: [top] plus the section's top inset.
  double get headerTop => top + grid.insets.top;

  /// Header band height.
  double get headerExtent => grid.headerExtent;

  /// Content y of the first row.
  double get rowsTop => headerTop + grid.headerExtent;

  /// Row pitch.
  double get rowExtent => grid.cellHeight;

  /// Content y where the last row ends (the header's bottom when empty).
  double get rowsBottom => rowsTop + rowCount * grid.cellHeight;

  /// Content y where the band ends: [rowsBottom] plus the bottom inset.
  double get bottom => rowsBottom + grid.insets.bottom;

  /// Flat adapter index of the section's last row (its header when empty).
  int get lastFlatIndex => flatIndex + rowCount;
}

/// The section bands of a catalog and the extent they add up to.
final class CatalogSectionBands {
  /// Creates the bands and the total [contentExtent].
  const CatalogSectionBands({required this.bands, required this.contentExtent});

  /// One band per section, in display order.
  final List<CatalogSectionBand> bands;

  /// Total content height (`padding.top` … `padding.bottom` included).
  final double contentExtent;
}

/// Skeleton cells [section] paints after its leaves: none unless it is
/// loading or failed, else [CatalogSection.skeletonCount] or one row of its
/// columns.
int catalogSkeletonCount(CatalogSection section, CatalogGridMetrics grid) =>
    section.state == CatalogSectionState.loaded
    ? 0
    : section.skeletonCount ?? grid.spanCount;

/// Whether [section] shows its empty message: loaded, no leaves, a message.
bool catalogShowsEmptyMessage(CatalogSection section) =>
    section.state == CatalogSectionState.loaded &&
    section.leaves.isEmpty &&
    section.emptyMessage != null;

/// Rows [section] takes under its header: the rows of its leaves and skeleton
/// cells, or the one row of its empty message.
int catalogSectionRowCount(CatalogSection section, CatalogGridMetrics grid) =>
    catalogShowsEmptyMessage(section)
    ? 1
    : grid.rowCountFor(
        section.leaves.length + catalogSkeletonCount(section, grid),
      );

/// Lays [sections] out as bands, each by its own layout resolved against the
/// viewport defaults.
///
/// Pure transform; O(sections). [projectCatalogSlots] places the slots on
/// these bands, so landing math on bands and the painted slots cannot differ.
CatalogSectionBands projectCatalogSectionBands({
  required List<CatalogSection> sections,
  required int spanCount,
  required double cellExtent,
  required double headerExtent,
  required EdgeInsets padding,
  required double maxWidth,
  TextDirection textDirection = TextDirection.ltr,
}) {
  final bands = <CatalogSectionBand>[];
  var y = padding.top;
  var flat = 0;
  for (final section in sections) {
    final grid = resolveCatalogGrid(
      section.layout,
      spanCount: spanCount,
      cellExtent: cellExtent,
      headerExtent: headerExtent,
      padding: padding,
      maxWidth: maxWidth,
      textDirection: textDirection,
    );
    final band = CatalogSectionBand(
      top: y,
      grid: grid,
      rowCount: catalogSectionRowCount(section, grid),
      flatIndex: flat,
    );
    bands.add(band);
    y = band.bottom;
    flat += 1 + band.rowCount;
  }
  return CatalogSectionBands(bands: bands, contentExtent: y + padding.bottom);
}

/// Result of projecting catalog sections into absolute layout slots.
final class CatalogSlotProjection {
  /// Creates a projection with flattened [slots], the [bands] they were placed
  /// on and the total [contentExtent].
  const CatalogSlotProjection({
    required this.slots,
    required this.bands,
    required this.contentExtent,
  });

  /// Flattened header + leaf slots in paint / extent order (top → bottom).
  final List<CatalogLayoutSlot> slots;

  /// The per-section bands the slots were placed on.
  final List<CatalogSectionBand> bands;

  /// Total content height for extent scroll (`padding.top` … `padding.bottom`).
  ///
  /// This is the scrollable content size — not the viewport height.
  final double contentExtent;
}

/// Projects [sections] into absolute header/leaf slots for extent layout.
///
/// Pure transform — no I/O, no asset binds, no listeners. Safe to call from
/// layout. Empty [sections] yields `contentExtent == padding.vertical` and an
/// empty [CatalogSlotProjection.slots] list.
///
/// [spanCount], [cellExtent] and [headerExtent] are the **defaults** of a
/// section whose [CatalogSection.layout] leaves them unset.
///
/// ## Geometry rules
///
/// - Starts at `y = padding.top`.
/// - Each section: its top inset, a header of its header extent, then leaves in
///   row-major order across its own columns, then its bottom inset. Sections
///   with different spans, cell sizes and insets stack in one ascending list.
/// - Cells fill each row start to end: column `0` is at the left edge in a
///   left-to-right grid and at the right edge in a right-to-left one. The
///   direction is the section's own or [textDirection], and changes only x.
/// - Cell width = `(maxWidth − padding.horizontal − insets.horizontal) /
///   spanCount` when usable width > 0; otherwise falls back to the cell extent
///   (degenerate narrow constraint).
/// - Empty leaf lists still emit the header; they do **not** add a row, unless
///   the section is loaded with an empty message (one message row) or is
///   loading or failed (skeleton cells continuing the grid after the leaves).
/// - Ends with `y += padding.bottom` → [CatalogSlotProjection.contentExtent].
///
/// The default [spanCount] MUST be ≥ 1 (division). Zero/negative extents
/// collapse bands but do not assert.
CatalogSlotProjection projectCatalogSlots({
  required List<CatalogSection> sections,
  required int spanCount,
  required double cellExtent,
  required double headerExtent,
  required EdgeInsets padding,
  required double maxWidth,
  TextDirection textDirection = TextDirection.ltr,
}) {
  final projected = projectCatalogSectionBands(
    sections: sections,
    spanCount: spanCount,
    cellExtent: cellExtent,
    headerExtent: headerExtent,
    padding: padding,
    maxWidth: maxWidth,
    textDirection: textDirection,
  );
  final slots = <CatalogLayoutSlot>[];
  for (var s = 0; s < sections.length; s++) {
    final section = sections[s];
    final band = projected.bands[s];
    final grid = band.grid;
    slots.add(
      CatalogLayoutSlot.header(
        top: band.headerTop,
        height: grid.headerExtent,
        left: grid.left,
        width: grid.usableWidth,
        title: section.title,
        sectionId: section.id,
        action: section.action,
        textDirection: grid.textDirection,
      ),
    );
    final leaves = section.leaves;
    final firstLeft = grid.startCellLeft;
    final step = grid.columnStep;
    for (var i = 0; i < leaves.length; i++) {
      slots.add(
        CatalogLayoutSlot.leaf(
          top: band.rowsTop + (i ~/ grid.spanCount) * grid.cellHeight,
          height: grid.cellHeight,
          left: firstLeft + (i % grid.spanCount) * step,
          width: grid.cellWidth,
          sectionId: section.id,
          index: i,
          leaf: leaves[i],
          contentBox: section.contentBox,
          placeholderStyle: section.placeholderStyle,
          glyphExtent: grid.glyphExtent,
        ),
      );
    }
    final skeletons = catalogSkeletonCount(section, grid);
    for (var i = leaves.length; i < leaves.length + skeletons; i++) {
      slots.add(
        CatalogLayoutSlot.skeleton(
          top: band.rowsTop + (i ~/ grid.spanCount) * grid.cellHeight,
          height: grid.cellHeight,
          left: firstLeft + (i % grid.spanCount) * step,
          width: grid.cellWidth,
          contentBox: section.contentBox ?? CatalogContentBox.glyph,
          style: section.placeholderStyle ?? CatalogPlaceholderStyle.circle,
          glyphExtent: grid.glyphExtent,
        ),
      );
    }
    if (catalogShowsEmptyMessage(section)) {
      slots.add(
        CatalogLayoutSlot.message(
          top: band.rowsTop,
          height: grid.cellHeight,
          left: grid.left,
          width: grid.usableWidth,
          text: section.emptyMessage!,
        ),
      );
    }
  }
  return CatalogSlotProjection(
    slots: slots,
    bands: projected.bands,
    contentExtent: projected.contentExtent,
  );
}
