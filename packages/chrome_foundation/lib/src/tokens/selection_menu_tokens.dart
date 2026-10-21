import 'dart:ui' show Brightness, Color;

import 'package:chrome_foundation/src/palette/chrome_palette.dart';
import 'package:meta/meta.dart';

/// Colours of the selection menu: the floating card that offers the clipboard
/// and formatting actions over a text selection.
///
/// Derived from a [ChromePalette] by [SelectionMenuTokens.fromPalette]; a host
/// overrides single fields with [copyWith] or supplies the whole group to a
/// `ChromeThemeScope`. The card's elevation and corner radius are the
/// component's metrics, kept here as constants so the menu and its hosts read
/// one number (ADR 027: geometry is not themed, so they are constants, not
/// fields).
///
/// Press, hover and focus washes are the Material widgets' own for the host's
/// theme, so the group has no field for them.
@immutable
final class SelectionMenuTokens {
  /// A selection menu token group with every colour given.
  const SelectionMenuTokens({
    required this.background,
    required this.text,
    required this.divider,
    required this.shadow,
    required this.pageDim,
  });

  /// The default mapping of [palette] onto menu fields.
  ///
  /// The card is the palette's raised surface and the text its on-surface
  /// colour: for a palette built from a colour scheme these are
  /// `surfaceContainerHigh` and `onSurface`, which is how a Material menu is
  /// coloured. The divider is the separator at half its own opacity (the
  /// scheme's `outlineVariant` at 0.5), so a palette whose separator is
  /// already translucent gets a fainter line; a host that wants the Material
  /// look builds its palette from its colour scheme. The shadow is black at
  /// 0.45. The page dim, the scrim over the main row while the More page
  /// slides in, is black at `0x18` on a light palette and `0x40` on a dark
  /// one.
  factory SelectionMenuTokens.fromPalette(ChromePalette palette) =>
      SelectionMenuTokens(
        background: palette.surfaceRaised,
        text: palette.onSurface,
        divider: palette.separator.withValues(alpha: palette.separator.a * 0.5),
        shadow: const Color(0xFF000000).withValues(alpha: 0.45),
        pageDim: switch (palette.brightness) {
          Brightness.light => const Color(0x18000000),
          Brightness.dark => const Color(0x40000000),
        },
      );

  /// Elevation of the card, in logical pixels.
  static const double elevation = 3;

  /// Corner radius of the card, in logical pixels.
  static const double cornerRadius = 12;

  /// Card fill, and the fill of each page.
  final Color background;

  /// Item and back-row text, and the icons.
  final Color text;

  /// Hairline between the More page's list and its back row.
  final Color divider;

  /// Shadow colour of the card.
  final Color shadow;

  /// The scrim over the main row at the end of a page turn; its alpha is the
  /// maximum, reached when the More page is fully open.
  final Color pageDim;

  /// A copy with the named fields replaced.
  SelectionMenuTokens copyWith({
    Color? background,
    Color? text,
    Color? divider,
    Color? shadow,
    Color? pageDim,
  }) => SelectionMenuTokens(
    background: background ?? this.background,
    text: text ?? this.text,
    divider: divider ?? this.divider,
    shadow: shadow ?? this.shadow,
    pageDim: pageDim ?? this.pageDim,
  );

  /// Interpolates every field between [a] and [b].
  // Flutter's `T.lerp(a, b, t)` shape; a constructor cannot take two sources.
  // ignore: prefer_constructors_over_static_methods
  static SelectionMenuTokens lerp(
    SelectionMenuTokens a,
    SelectionMenuTokens b,
    double t,
  ) => SelectionMenuTokens(
    background: Color.lerp(a.background, b.background, t)!,
    text: Color.lerp(a.text, b.text, t)!,
    divider: Color.lerp(a.divider, b.divider, t)!,
    shadow: Color.lerp(a.shadow, b.shadow, t)!,
    pageDim: Color.lerp(a.pageDim, b.pageDim, t)!,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SelectionMenuTokens &&
          background == other.background &&
          text == other.text &&
          divider == other.divider &&
          shadow == other.shadow &&
          pageDim == other.pageDim;

  @override
  int get hashCode => Object.hash(background, text, divider, shadow, pageDim);

  @override
  String toString() => 'SelectionMenuTokens(background: $background)';
}
