import 'package:flutter/widgets.dart' show Canvas, Color, IconData, Rect;
import 'package:meta/meta.dart';

/// The trailing action of a section header: a label, an icon, or both, and the
/// id the viewport reports when the user taps it.
///
/// The viewport paints it at the end of the header band, in the header text
/// style, and owns its hit area: a tap anywhere in the band's trailing area
/// the action occupies (at least [minHitWidth] wide, the whole
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
    this.painter,
    this.semanticLabel,
  }) : assert(id != '', 'An action is reported by its id.'),
       assert(
         label != null || icon != null || painter != null,
         'An action with neither label nor icon cannot be seen or tapped.',
       ),
       assert(
         icon == null || painter == null,
         'An action has one icon: a glyph or a painter.',
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

  /// Least width of an action's hit area, in logical pixels, so an icon-only
  /// action is not a sliver to hit.
  static const double minHitWidth = 48;

  /// Side of the box a [painter] draws in, in logical pixels.
  static const double iconExtent = 24;

  /// Draws the icon in place of [icon]: called with an [iconExtent]
  /// square box and the header text colour, for an icon no font has. Compared
  /// by identity, so pass the same function across snapshots (a top-level or
  /// static one).
  final CatalogActionIconPainter? painter;

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
      other.painter == painter &&
      other.semanticLabel == semanticLabel;

  @override
  int get hashCode => Object.hash(id, label, icon, painter, semanticLabel);

  @override
  String toString() => 'CatalogSectionAction($id)';
}

/// Draws a header action's icon in [box] in [color]; see
/// [CatalogSectionAction.painter].
typedef CatalogActionIconPainter =
    void Function(Canvas canvas, Rect box, Color color);
