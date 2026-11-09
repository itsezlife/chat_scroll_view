import 'dart:ui' show Color;

import 'package:chrome_foundation/src/palette/chrome_palette.dart';
import 'package:meta/meta.dart';

/// Colours of a **bulletin**: the short notice shown over a surface for a few
/// seconds, with an optional Undo or button.
///
/// The card's geometry (margin, radius, height) belongs to the bulletin's
/// platform policy, not to this group; glass and blur belong to the
/// bulletin's frame builder, which paints over [background].
@immutable
final class BulletinTokens {
  /// A token group with every colour given.
  const BulletinTokens({
    required this.background,
    required this.foreground,
    required this.accent,
    required this.countdown,
  });

  /// The default group: the dark card, [referenceAndroid], on
  /// every palette but the two high-contrast presets, which get
  /// [highContrast].
  ///
  /// The notice stays dark in day and night themes, so
  /// it stands out over either; the palette's colours do not change it. A
  /// host that wants a palette-coloured card overrides the group.
  factory BulletinTokens.fromPalette(ChromePalette palette) =>
      palette == const ChromePalette.highContrastLight() ||
          palette == const ChromePalette.highContrastDark()
      ? highContrast
      : referenceAndroid;

  /// The undo notice's background, info and cancel colours.
  static const BulletinTokens referenceAndroid = BulletinTokens(
    background: Color(0xEA272F38),
    foreground: Color(0xFFFFFFFF),
    accent: Color(0xFF85CAFF),
    countdown: Color(0xFFFFFFFF),
  );

  /// The desktop toast: background #2c3033 at 0xe5 alpha and white foreground,
  /// with the link colours its text and buttons take from the desktop palette.
  static const BulletinTokens referenceDesktop = BulletinTokens(
    background: Color(0xE52C3033),
    foreground: Color(0xFFFFFFFF),
    accent: Color(0xFF4DB8FF),
    countdown: Color(0xFFFFFFFF),
  );

  /// The dark card made opaque and its accent lighter, so the action label
  /// reaches 7:1 as the high-contrast palettes' text does.
  static const BulletinTokens highContrast = BulletinTokens(
    background: Color(0xFF000000),
    foreground: Color(0xFFFFFFFF),
    accent: Color(0xFFA8D8FF),
    countdown: Color(0xFFFFFFFF),
  );

  /// The card fill, under any glass or blur the frame adds.
  final Color background;

  /// Title, message and icon tint.
  final Color foreground;

  /// The action label (Undo, a button) and links in the message.
  final Color accent;

  /// The countdown ring and its digits.
  final Color countdown;

  /// A copy with the named fields replaced.
  BulletinTokens copyWith({
    Color? background,
    Color? foreground,
    Color? accent,
    Color? countdown,
  }) => BulletinTokens(
    background: background ?? this.background,
    foreground: foreground ?? this.foreground,
    accent: accent ?? this.accent,
    countdown: countdown ?? this.countdown,
  );

  /// Interpolates every field between [a] and [b].
  // Flutter's `T.lerp(a, b, t)` shape; a constructor cannot take two sources.
  // ignore: prefer_constructors_over_static_methods
  static BulletinTokens lerp(BulletinTokens a, BulletinTokens b, double t) =>
      BulletinTokens(
        background: Color.lerp(a.background, b.background, t)!,
        foreground: Color.lerp(a.foreground, b.foreground, t)!,
        accent: Color.lerp(a.accent, b.accent, t)!,
        countdown: Color.lerp(a.countdown, b.countdown, t)!,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BulletinTokens &&
          background == other.background &&
          foreground == other.foreground &&
          accent == other.accent &&
          countdown == other.countdown;

  @override
  int get hashCode => Object.hash(background, foreground, accent, countdown);

  @override
  String toString() => 'BulletinTokens(background: $background)';
}
