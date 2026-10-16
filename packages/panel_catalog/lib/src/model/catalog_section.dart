import 'package:panel_catalog/src/data/catalog_snapshot.dart';
import 'package:panel_catalog/src/model/catalog_glyph_box.dart';
import 'package:panel_catalog/src/model/catalog_leaf.dart';
import 'package:panel_catalog/src/model/section_layout.dart';

/// One titled band of leaves in the catalog.
///
/// Participates in extent layout: every section emits a header band even when
/// [leaves] is empty, so category strip jumps can land under reserved header
/// space. Leaf rows follow the header in display order; the row count is
/// `ceil(leaves.length / spanCount)` of the section's own [layout].
///
/// [id] MUST stay stable across [CatalogSnapshot] publications for the same
/// logical section (category / pack): it is the first half of a leaf's hit
/// identity ([CatalogLeafHit.sectionId]) and of host jump maps. [title] is
/// host-localized display copy: the viewport paints it but does **not** own
/// l10n; do not put raw l10n keys here unless the host intentionally paints
/// keys.
///
/// This type is immutable by convention: replace the section (or the whole
/// sections list) on mutation rather than editing [leaves] in place after the
/// data source has published it.
final class CatalogSection {
  /// Creates a section with stable [id], display [title], and [leaves],
  /// laid out by [layout] (the viewport defaults when null).
  ///
  /// [contentBox] and [placeholderStyle] override what each leaf's facts say
  /// for every leaf of the section.
  const CatalogSection({
    required this.id,
    required this.title,
    required this.leaves,
    this.layout,
    this.contentBox,
    this.placeholderStyle,
  });

  /// Stable section identity (category / pack id).
  ///
  /// MUST be unique among siblings in a single [CatalogSnapshot.sections]
  /// snapshot: hits and jumps are addressed by it.
  final String id;

  /// Host-localized section title for layout headers.
  final String title;

  /// Leaves in display order (read-only to the viewport).
  ///
  /// Empty list still emits a header band; no trailing row height is added
  /// for zero leaves.
  final List<CatalogLeaf> leaves;

  /// The section's geometry, or null to use the viewport's default
  /// `spanCount`, `cellExtent` and `headerExtent` with no insets.
  final SectionLayout? layout;

  /// The box this section's leaves are asked for and drawn in, or null for what
  /// each leaf's facts say ([CatalogLeaf.contentBox]). A sticker section that
  /// shows its stickers inset, or an emoji section of large custom emoji,
  /// states it here instead of changing the leaves.
  final CatalogContentBox? contentBox;

  /// The stand-in of this section's leaves, or null for what each leaf's facts
  /// say ([CatalogLeaf.placeholderStyle]).
  final CatalogPlaceholderStyle? placeholderStyle;
}
