import 'package:flutter/widgets.dart';

/// How an anchored popup looks: its width, corners, shadow and the scale it
/// grows from.
///
/// The width is required and the other fields default to nothing drawn. No
/// reference client's dimensions are shipped here: a host passes the ones its
/// design calls for. The height is not part of the style; the presentation
/// policy sizes it from the window.
@immutable
final class AnchoredPopupStyle {
  /// A style of [width] logical pixels.
  const AnchoredPopupStyle({
    required this.width,
    this.cornerRadius = 0,
    this.shadows = const <BoxShadow>[],
    this.scaleBegin = 0.9,
  }) : assert(width > 0, 'width must be positive'),
       assert(cornerRadius >= 0, 'cornerRadius must not be negative'),
       assert(
         scaleBegin > 0 && scaleBegin <= 1,
         'scaleBegin must be in (0, 1]',
       );

  /// The width of the popup. Narrower when the window is.
  final double width;

  /// The radius of the popup's four corners.
  final double cornerRadius;

  /// The shadows drawn behind the popup.
  final List<BoxShadow> shadows;

  /// The scale the popup has when it starts to appear and when it has
  /// finished disappearing, around its bottom-end corner. `1` only fades.
  ///
  /// A chosen default, not checked against a reference client.
  final double scaleBegin;

  @override
  bool operator ==(Object other) =>
      other is AnchoredPopupStyle &&
      other.width == width &&
      other.cornerRadius == cornerRadius &&
      other.scaleBegin == scaleBegin &&
      _sameShadows(other.shadows, shadows);

  @override
  int get hashCode =>
      Object.hash(width, cornerRadius, scaleBegin, Object.hashAll(shadows));

  @override
  String toString() => 'AnchoredPopupStyle(width: $width)';

  static bool _sameShadows(List<BoxShadow> a, List<BoxShadow> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
