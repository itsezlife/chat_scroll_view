import 'dart:ui' show Brightness, Color;

import 'package:chrome_foundation/src/palette/chrome_palette.dart';
import 'package:meta/meta.dart';

/// Colours of the selection menu: the floating card that offers formatting
/// over a text selection.
///
/// Derived from a [ChromePalette] by [SelectionMenuTokens.fromPalette]; a host
/// overrides single fields with [copyWith] or supplies the whole group to a
/// `ChromeThemeScope`. The card's elevation and corner radius are the
/// component's metrics, kept here as constants so the menu and its hosts read
/// one number (ADR 027: geometry is
/// not themed, so they are constants, not fields).
@immutable
final class SelectionMenuTokens {
  /// A selection menu token group with every colour given.
  const SelectionMenuTokens({
    required this.background,
    required this.text,
    required this.pressHighlight,
    required this.divider,
  });

  /// The default mapping of [palette] onto menu fields.
  ///
  /// A light palette gets the reference client's default theme verbatim
  /// (`windowBackgroundWhite`, `windowBackgroundWhiteBlackText`,
  /// `listSelector`, `divider`): its text and divider are not palette roles,
  /// so no mapping of roles reproduces them. A dark palette derives from its
  /// roles instead, since the reference values for a dark card were not
  /// measured: the raised surface, the primary text colour, and that colour
  /// at the same low alphas the light press highlight and a visible divider
  /// use.
  factory SelectionMenuTokens.fromPalette(ChromePalette palette) =>
      switch (palette.brightness) {
        Brightness.light => const SelectionMenuTokens(
          background: Color(0xFFFFFFFF),
          text: Color(0xFF1A1D21),
          pressHighlight: Color(0x0F000000),
          divider: Color(0xFFD9D9D9),
        ),
        Brightness.dark => SelectionMenuTokens(
          background: palette.surfaceRaised,
          text: palette.onSurface,
          pressHighlight: palette.onSurface.withAlpha(0x0F),
          divider: palette.onSurface.withAlpha(0x26),
        ),
      };

  /// Elevation of the card, in logical pixels (the reference client's 1 dp).
  static const double elevation = 1;

  /// Corner radius of the card, in logical pixels.
  static const double cornerRadius = 12;

  /// Card fill, and the fill of the overflow page.
  final Color background;

  /// Item and back-row text.
  final Color text;

  /// Wash over an item while it is pressed.
  final Color pressHighlight;

  /// Hairline above the back row.
  final Color divider;

  /// A copy with the named fields replaced.
  SelectionMenuTokens copyWith({
    Color? background,
    Color? text,
    Color? pressHighlight,
    Color? divider,
  }) => SelectionMenuTokens(
    background: background ?? this.background,
    text: text ?? this.text,
    pressHighlight: pressHighlight ?? this.pressHighlight,
    divider: divider ?? this.divider,
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
    pressHighlight: Color.lerp(a.pressHighlight, b.pressHighlight, t)!,
    divider: Color.lerp(a.divider, b.divider, t)!,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SelectionMenuTokens &&
          background == other.background &&
          text == other.text &&
          pressHighlight == other.pressHighlight &&
          divider == other.divider;

  @override
  int get hashCode => Object.hash(background, text, pressHighlight, divider);

  @override
  String toString() => 'SelectionMenuTokens(background: $background)';
}
