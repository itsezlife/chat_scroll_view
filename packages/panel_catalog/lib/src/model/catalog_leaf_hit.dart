import 'package:meta/meta.dart';
import 'package:panel_catalog/src/model/catalog_leaf.dart';

/// The cell an interaction landed on.
///
/// Identity is [sectionId] and [index] (the leaf's position in its section's
/// leaves): that is the cell. The same content key shown in two sections, or
/// twice in one, is two hits, which is why a host acts on the position and not
/// on [CatalogLeaf.key]. [leaf] is what the cell holds, with the host's
/// [CatalogLeaf.tag] intact.
@immutable
final class CatalogLeafHit {
  /// Creates the hit on cell [index] of section [sectionId] holding [leaf].
  const CatalogLeafHit({
    required this.sectionId,
    required this.index,
    required this.leaf,
  });

  /// [CatalogSection.id] of the section the cell belongs to.
  final String sectionId;

  /// Position of the cell in its section's leaves, from zero.
  final int index;

  /// The leaf the cell holds.
  final CatalogLeaf leaf;

  @override
  bool operator ==(Object other) =>
      other is CatalogLeafHit &&
      other.sectionId == sectionId &&
      other.index == index;

  @override
  int get hashCode => Object.hash(sectionId, index);

  @override
  String toString() => 'CatalogLeafHit($sectionId, $index, ${leaf.key})';
}
