import 'package:flutter/widgets.dart';

/// How the docked section looks: the width of a dock nobody has resized, and an
/// optional separator.
///
/// What bounds a dock's width, and where the user may drag it, is the
/// policy's (`PanelPresentationPolicy.dockWidthIn`); nothing is drawn here
/// unless the host asks.
@immutable
final class DockedStyle {
  /// A style whose dock is [width] logical pixels until the user resizes it,
  /// or the policy's narrowest when null.
  const DockedStyle({this.width, this.separator})
    : assert(width == null || width > 0, 'width must be positive');

  /// The width of a dock nobody has dragged, held to the policy's bounds. The
  /// dock's width is its inline-end occupancy. Narrower when the box the view
  /// fills is.
  final double? width;

  /// The colour of a one-pixel line along the section's start edge, or null
  /// for none.
  final Color? separator;

  @override
  bool operator ==(Object other) =>
      other is DockedStyle &&
      other.width == width &&
      other.separator == separator;

  @override
  int get hashCode => Object.hash(width, separator);

  @override
  String toString() => 'DockedStyle(width: $width)';
}
