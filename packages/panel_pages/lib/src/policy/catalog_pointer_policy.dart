import 'package:flutter/foundation.dart' show immutable, kIsWeb;
import 'package:panel_catalog/panel_catalog.dart';

/// What a catalog page offers a mouse for taking content out of the library,
/// per platform family: a desktop app's or a browser's.
///
/// Read only under `PanelArrangement.pointer`; a touch page offers neither
/// the header cross nor the badge. [current] is the running app's family;
/// a test names a variant.
@immutable
sealed class CatalogPointerPolicy {
  const CatalogPointerPolicy._();

  /// A desktop app's: see [CatalogPointerPolicy$Desktop].
  const factory CatalogPointerPolicy.desktop() = CatalogPointerPolicy$Desktop;

  /// A browser's: see [CatalogPointerPolicy$Web].
  const factory CatalogPointerPolicy.web() = CatalogPointerPolicy$Web;

  /// The family of the running app: [CatalogPointerPolicy$Web] in a browser,
  /// [CatalogPointerPolicy$Desktop] otherwise.
  static const CatalogPointerPolicy current = kIsWeb
      ? CatalogPointerPolicy$Web()
      : CatalogPointerPolicy$Desktop();

  /// Whether the header of a pack the user installed ends in a cross that
  /// removes the pack.
  bool get packHeaderRemoves;

  /// The badge a hovered removable cell shows.
  CatalogLeafRemoveBadge get removeBadge;
}

/// [CatalogPointerPolicy.desktop]: an installed pack's header removes it, and
/// a removable cell shows the square [CatalogLeafRemoveBadge.pointer].
final class CatalogPointerPolicy$Desktop extends CatalogPointerPolicy {
  /// The desktop policy.
  const CatalogPointerPolicy$Desktop() : super._();

  @override
  bool get packHeaderRemoves => true;

  @override
  CatalogLeafRemoveBadge get removeBadge => CatalogLeafRemoveBadge.pointer;

  @override
  bool operator ==(Object other) => other is CatalogPointerPolicy$Desktop;

  @override
  int get hashCode => (CatalogPointerPolicy$Desktop).hashCode;
}

/// [CatalogPointerPolicy.web]: only the recents' header carries a cross (a
/// pack's has none), and a removable cell shows the round
/// [CatalogLeafRemoveBadge.web].
final class CatalogPointerPolicy$Web extends CatalogPointerPolicy {
  /// The web policy.
  const CatalogPointerPolicy$Web() : super._();

  @override
  bool get packHeaderRemoves => false;

  @override
  CatalogLeafRemoveBadge get removeBadge => CatalogLeafRemoveBadge.web;

  @override
  bool operator ==(Object other) => other is CatalogPointerPolicy$Web;

  @override
  int get hashCode => (CatalogPointerPolicy$Web).hashCode;
}
