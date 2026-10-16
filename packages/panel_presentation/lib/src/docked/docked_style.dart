import 'package:flutter/widgets.dart';

/// How the docked section looks: its width and an optional separator.
///
/// The width is required and nothing else is drawn by default. No reference
/// client's dimensions are shipped here: a host passes the ones its design
/// calls for.
@immutable
final class DockedStyle {
  /// A style of [width] logical pixels.
  const DockedStyle({required this.width, this.separator})
    : assert(width > 0, 'width must be positive');

  /// The width of the section, which is its inline-end occupancy. Narrower
  /// when the box the view fills is.
  final double width;

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
