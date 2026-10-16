import 'package:flutter/widgets.dart' show IconData;
import 'package:meta/meta.dart';

/// The trailing action of a section header: a label, an icon, or both, and the
/// id the viewport reports when the user taps it.
///
/// The viewport paints it at the end of the header band, in the header text
/// style, and owns its hit area: a tap anywhere in the band's trailing area
/// the action occupies (at least [kCatalogActionMinHitWidth] wide, the whole
/// band tall) reports `onSectionAction(sectionId, id)`. The viewport decides
/// nothing about what the action does.
@immutable
final class CatalogSectionAction {
  /// Creates an action reported as [id], painted as [label] and / or [icon].
  ///
  /// [id] must not be empty, and the action needs a label or an icon to be
  /// seen at all.
  const CatalogSectionAction({
    required this.id,
    this.label,
    this.icon,
    this.semanticLabel,
  }) : assert(id != '', 'An action is reported by its id.'),
       assert(
         label != null || icon != null,
         'An action with neither label nor icon cannot be seen or tapped.',
       );

  /// What `onSectionAction` reports. Stable for the same action across
  /// snapshots.
  final String id;

  /// Host-localized label, painted first, or null for an icon-only action.
  final String? label;

  /// Glyph painted after the label (or alone), or null for a label-only
  /// action. Drawn as text from its font, so any icon font the host bundles
  /// works.
  final IconData? icon;

  /// What a screen reader says for the action, or null to read [label].
  ///
  /// An icon-only action has no [label] to fall back on: give it one, or it is
  /// a button without a name. Host-localized, like [label].
  final String? semanticLabel;

  @override
  bool operator ==(Object other) =>
      other is CatalogSectionAction &&
      other.id == id &&
      other.label == label &&
      other.icon == icon &&
      other.semanticLabel == semanticLabel;

  @override
  int get hashCode => Object.hash(id, label, icon, semanticLabel);

  @override
  String toString() => 'CatalogSectionAction($id)';
}

/// Least width of an action's hit area, in logical pixels, so an icon-only
/// action is not a sliver to hit.
const double kCatalogActionMinHitWidth = 48;
