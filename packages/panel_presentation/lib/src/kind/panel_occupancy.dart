import 'package:meta/meta.dart';

/// The space a presentation takes from its host, in logical pixels.
///
/// **Occupancy** is data the host aggregates: it adds the composer's extent
/// and [bottom] into the viewport's bottom padding and applies [inlineEnd] in
/// layout, mirrored in a right-to-left layout. The presentation never reaches
/// into the host's layout to do it for them.
///
/// Both extents are non-negative. [bottom] is the space under the content,
/// [inlineEnd] the space at the reading end (right in left-to-right, left in
/// right-to-left).
@immutable
final class PanelOccupancy {
  /// An occupancy of [bottom] under the content and [inlineEnd] beside it.
  const PanelOccupancy({this.bottom = 0, this.inlineEnd = 0})
    : assert(bottom >= 0, 'bottom must not be negative'),
      assert(inlineEnd >= 0, 'inlineEnd must not be negative');

  /// Takes no space: what an anchored popup publishes.
  static const PanelOccupancy zero = PanelOccupancy();

  /// The extent under the content.
  final double bottom;

  /// The extent at the reading end of the content.
  final double inlineEnd;

  /// Whether nothing is taken on either axis.
  bool get isZero => bottom == 0 && inlineEnd == 0;

  @override
  bool operator ==(Object other) =>
      other is PanelOccupancy &&
      other.bottom == bottom &&
      other.inlineEnd == inlineEnd;

  @override
  int get hashCode => Object.hash(bottom, inlineEnd);

  @override
  String toString() => 'PanelOccupancy(bottom: $bottom, inlineEnd: $inlineEnd)';
}
