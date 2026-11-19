import 'dart:ui' show Brightness, Color;

import 'package:chrome_foundation/src/palette/chrome_palette.dart';
import 'package:meta/meta.dart';

/// Colours of the **attach sheet**: the mobile container a user picks media
/// and files to send from.
///
/// The sheet's geometry and motion (insets, radius, springs, how dark the
/// dim gets) belong to the sheet's platform policy, not to this group.
@immutable
final class AttachTokens {
  /// A token group with every colour given.
  const AttachTokens({
    required this.scrim,
    required this.background,
    required this.grabber,
    required this.header,
  });

  /// The group derived from [palette]: the sheet on the raised surface, a
  /// black scrim, and the grabber in the text colour at 7 % on a light
  /// palette and 20 % on a dark one.
  factory AttachTokens.fromPalette(ChromePalette palette) => AttachTokens(
    scrim: const Color(0xFF000000),
    background: palette.surfaceRaised,
    grabber: palette.onSurface.withValues(
      alpha: palette.brightness == Brightness.light ? 0.07 : 0.2,
    ),
    header: palette.surfaceRaised,
  );

  /// The colour dimming the screen behind the sheet, at full strength; the
  /// policy's dim opacity scales it.
  final Color scrim;

  /// The sheet's fill.
  final Color background;

  /// The grabber pill at the sheet's top edge.
  final Color grabber;

  /// The header that fades in once the sheet is pinned at the top.
  final Color header;

  /// A copy with the named fields replaced.
  AttachTokens copyWith({
    Color? scrim,
    Color? background,
    Color? grabber,
    Color? header,
  }) => AttachTokens(
    scrim: scrim ?? this.scrim,
    background: background ?? this.background,
    grabber: grabber ?? this.grabber,
    header: header ?? this.header,
  );

  /// Interpolates every field between [a] and [b].
  // Flutter's `T.lerp(a, b, t)` shape; a constructor cannot take two sources.
  // ignore: prefer_constructors_over_static_methods
  static AttachTokens lerp(AttachTokens a, AttachTokens b, double t) =>
      AttachTokens(
        scrim: Color.lerp(a.scrim, b.scrim, t)!,
        background: Color.lerp(a.background, b.background, t)!,
        grabber: Color.lerp(a.grabber, b.grabber, t)!,
        header: Color.lerp(a.header, b.header, t)!,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AttachTokens &&
          scrim == other.scrim &&
          background == other.background &&
          grabber == other.grabber &&
          header == other.header;

  @override
  int get hashCode => Object.hash(scrim, background, grabber, header);

  @override
  String toString() => 'AttachTokens(background: $background)';
}
