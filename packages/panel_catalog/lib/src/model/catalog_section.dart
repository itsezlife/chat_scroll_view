import 'package:panel_catalog/src/model/catalog_leaf.dart';

/// One titled band of leaves in the catalog.
///
/// Participates in extent layout: every section emits a header band of
/// `headerExtent` even when [leaves] is empty, so category strip jumps can
/// land under reserved header space. Leaf rows follow the header in display
/// order; row count is `ceil(leaves.length / spanCount)`.
///
/// [id] MUST stay stable across [CatalogDataSource] notifies for the same
/// logical section (category / pack). Unstable ids break host jump maps and
/// any future section-keyed recycle. [title] is host-localized display copy —
/// the viewport paints it but does **not** own l10n; do not put raw l10n keys
/// here unless the host intentionally paints keys.
///
/// This type is immutable by convention: replace the section (or the whole
/// sections list) on mutation rather than editing [leaves] in place after the
/// data source has published it.
final class CatalogSection {
  /// Creates a section with stable [id], display [title], and [leaves].
  const CatalogSection({
    required this.id,
    required this.title,
    required this.leaves,
  });

  /// Stable section identity (category / pack id).
  ///
  /// MUST be unique among siblings in a single [CatalogDataSource.sections]
  /// snapshot when hosts key jumps or chrome by section.
  final String id;

  /// Host-localized section title for layout headers.
  final String title;

  /// Leaves in display order (read-only to the viewport).
  ///
  /// Empty list still emits a header band; no trailing row height is added
  /// for zero leaves.
  final List<CatalogLeaf> leaves;
}
