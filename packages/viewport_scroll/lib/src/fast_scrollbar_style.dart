import 'package:flutter/widgets.dart';

/// Builds the surface under a fast scrollbar's label or tab thumb (a glass
/// panel, say) in [shape], with [child] on it.
typedef FastScrollSurfaceBuilder =
    Widget Function(BuildContext context, ShapeBorder shape, Widget child);

/// The colours and text of a fast scrollbar, from the host's tokens: the
/// scrollbar knows no theme.
@immutable
final class FastScrollbarStyle {
  /// A style with every colour given.
  const FastScrollbarStyle({
    required this.thumbColor,
    required this.thumbIconColor,
    required this.labelColor,
    required this.labelTextStyle,
    this.surfaceBuilder,
  });

  /// The thumb's fill: the tab's disc or the line.
  final Color thumbColor;

  /// The tab thumb's chevrons.
  final Color thumbIconColor;

  /// The label's fill, when there is no [surfaceBuilder].
  final Color labelColor;

  /// The label's text.
  final TextStyle labelTextStyle;

  /// Builds the label's surface and the tab thumb's; null fills them with
  /// [labelColor] and [thumbColor].
  final FastScrollSurfaceBuilder? surfaceBuilder;

  @override
  bool operator ==(Object other) =>
      other is FastScrollbarStyle &&
      other.thumbColor == thumbColor &&
      other.thumbIconColor == thumbIconColor &&
      other.labelColor == labelColor &&
      other.labelTextStyle == labelTextStyle &&
      other.surfaceBuilder == surfaceBuilder;

  @override
  int get hashCode => Object.hash(
    thumbColor,
    thumbIconColor,
    labelColor,
    labelTextStyle,
    surfaceBuilder,
  );
}
