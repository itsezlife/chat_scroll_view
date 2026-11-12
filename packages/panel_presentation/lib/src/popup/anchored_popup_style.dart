import 'package:chrome_foundation/chrome_foundation.dart' show AppearMotion;
import 'package:flutter/widgets.dart';

/// What an anchored popup's surface is drawn as.
enum AnchoredPopupSurface {
  /// The composer's glass, so the panel over the chat reads as the composer
  /// does.
  glass,

  /// A solid fill of the panel's background colour.
  solid,
}

/// How an anchored popup looks: its width, corners, shadow, surface and the
/// motion it appears and leaves with.
///
/// The width is required and the other fields default to nothing drawn. No
/// dimensions are shipped here: a host passes the ones its
/// design calls for. The height is not part of the style; the presentation
/// policy sizes it from the window.
@immutable
final class AnchoredPopupStyle {
  /// A style of [width] logical pixels.
  const AnchoredPopupStyle({
    required this.width,
    this.cornerRadius = 0,
    this.shadows = const <BoxShadow>[],
    this.appear = const AppearMotion.grow(),
    this.hoverGutter = 10,
    this.edgeGap = 0,
    this.surface = AnchoredPopupSurface.glass,
  }) : assert(width > 0, 'width must be positive'),
       assert(cornerRadius >= 0, 'cornerRadius must not be negative'),
       assert(hoverGutter >= 0, 'hoverGutter must not be negative'),
       assert(edgeGap >= 0, 'edgeGap must not be negative');

  /// The width of the popup. Narrower when the window is.
  final double width;

  /// The radius of the popup's four corners.
  final double cornerRadius;

  /// The shadows drawn behind the popup.
  final List<BoxShadow> shadows;

  /// The **appear motion** the popup comes up and goes with, from its
  /// bottom-end corner, the one at the toggle: by default the desktop
  /// panel's grow. Its frames run over the presentation's show and hide
  /// roles.
  final AppearMotion appear;

  /// The room left between the popup and the composer it anchors to: above the
  /// composer's top edge and inside its end edge. The room is the same
  /// on both sides, so the popup is a card floating over the
  /// corner, not a sheet standing on the composer. The pointer's hover area
  /// still reaches the toggle across it.
  final double edgeGap;

  /// The transparent margin around the popup, on every side, that still
  /// counts as the popup to the pointer (and to an outside press). It is the
  /// room a [shadows] blur is drawn in: a pointer crossing the shadow has not
  /// left the popup. Below, it grows to reach the toggle, so there is no gap
  /// between the two where the pointer is over neither.
  final double hoverGutter;

  /// What the popup's surface is drawn as: glass by default.
  final AnchoredPopupSurface surface;

  @override
  bool operator ==(Object other) =>
      other is AnchoredPopupStyle &&
      other.width == width &&
      other.cornerRadius == cornerRadius &&
      other.appear == appear &&
      other.hoverGutter == hoverGutter &&
      other.edgeGap == edgeGap &&
      other.surface == surface &&
      _sameShadows(other.shadows, shadows);

  @override
  int get hashCode => Object.hash(
    width,
    cornerRadius,
    appear,
    hoverGutter,
    edgeGap,
    surface,
    Object.hashAll(shadows),
  );

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
