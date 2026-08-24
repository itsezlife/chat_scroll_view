import 'package:flutter/painting.dart';
import 'package:panel_catalog/src/model/catalog_leaf.dart';
import 'package:panel_catalog/src/model/catalog_section.dart';

/// One laid-out band in the flattened catalog projection (content coordinates).
///
/// Content y increases downward from the catalog top (`0` after top padding).
/// Slots are pure geometry + identity — no asset readiness, no paint mode.
/// The render object translates by `−offset` at paint time so content-y
/// [top] aligns into the viewport.
///
/// Use [CatalogLayoutSlot.header] / [CatalogLayoutSlot.leaf] factories.
sealed class CatalogLayoutSlot {
  /// Creates a slot spanning `[top, top + height)`.
  const CatalogLayoutSlot({required this.top, required this.height});

  /// Section title band (full usable width; title painted by the leaf painter).
  const factory CatalogLayoutSlot.header({
    required double top,
    required double height,
    required String title,
  }) = CatalogHeaderSlot;

  /// Leaf cell at column [left] with [width] (usually `usableWidth / span`).
  const factory CatalogLayoutSlot.leaf({
    required double top,
    required double height,
    required double left,
    required double width,
    required CatalogLeaf leaf,
  }) = CatalogLeafSlot;

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
    required this.title,
  });

  /// Host-localized section title (viewport paints; does not own l10n).
  final String title;
}

/// One leaf cell in the grid.
///
/// [left] / [width] are content-x; [top] / [height] are content-y.
final class CatalogLeafSlot extends CatalogLayoutSlot {
  /// Creates a leaf cell slot.
  const CatalogLeafSlot({
    required super.top,
    required super.height,
    required this.left,
    required this.width,
    required this.leaf,
  });

  /// Content x of the cell left edge (includes section padding.left).
  final double left;

  /// Cell width (`usableWidth / spanCount` when usable width > 0).
  final double width;

  /// Leaf projected into this cell (identity only).
  final CatalogLeaf leaf;
}

/// Result of projecting catalog sections into absolute layout slots.
final class CatalogSlotProjection {
  /// Creates a projection with flattened [slots] and total [contentExtent].
  const CatalogSlotProjection({
    required this.slots,
    required this.contentExtent,
  });

  /// Flattened header + leaf slots in paint / extent order (top → bottom).
  final List<CatalogLayoutSlot> slots;

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
/// ## Geometry rules
///
/// - Starts at `y = padding.top`.
/// - Each section: header of [headerExtent], then leaves in row-major order
///   across [spanCount] columns.
/// - Cell width = `(maxWidth − padding.horizontal) / spanCount` when usable
///   width > 0; otherwise falls back to [cellExtent] (degenerate narrow
///   constraint).
/// - Empty leaf lists still emit the header; they do **not** add a trailing
///   row height.
/// - Non-empty leaf lists advance `y` by [cellExtent] after the last partial
///   or full row.
/// - Ends with `y += padding.bottom` → [CatalogSlotProjection.contentExtent].
///
/// [spanCount] MUST be ≥ 1 (division). Zero/negative [cellExtent] /
/// [headerExtent] collapse bands but do not assert.
CatalogSlotProjection projectCatalogSlots({
  required List<CatalogSection> sections,
  required int spanCount,
  required double cellExtent,
  required double headerExtent,
  required EdgeInsets padding,
  required double maxWidth,
}) {
  final slots = <CatalogLayoutSlot>[];
  var y = padding.top;
  final usableWidth = (maxWidth - padding.horizontal).clamp(
    0.0,
    double.infinity,
  );
  final cellW = usableWidth > 0 ? usableWidth / spanCount : cellExtent;

  for (final section in sections) {
    slots.add(
      CatalogLayoutSlot.header(
        top: y,
        height: headerExtent,
        title: section.title,
      ),
    );
    y += headerExtent;

    final leaves = section.leaves;
    for (var i = 0; i < leaves.length; i++) {
      final leaf = leaves[i];
      final col = i % spanCount;
      if (col == 0 && i > 0) {
        y += cellExtent;
      }
      slots.add(
        CatalogLayoutSlot.leaf(
          top: y,
          height: cellExtent,
          left: padding.left + col * cellW,
          width: cellW,
          leaf: leaf,
        ),
      );
    }
    if (leaves.isNotEmpty) {
      y += cellExtent;
    }
  }

  y += padding.bottom;
  return CatalogSlotProjection(slots: slots, contentExtent: y);
}
