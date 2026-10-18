import 'dart:ui' show Color;

import 'package:chrome_foundation/src/palette/chrome_palette.dart';
import 'package:meta/meta.dart';

/// Colours of the pointer menu: the popup list opened at the pointer by a
/// secondary click, with rows, shortcut hints, separators and submenus.
///
/// Derived from a [ChromePalette] by [PointerMenuTokens.fromPalette]; a host
/// overrides single fields with [copyWith] or supplies the whole group to a
/// `ChromeThemeScope`. The popup's geometry (corner radius, row height,
/// padding, shadow) is not themed and lives in `PointerMenuMetrics`.
///
/// [referenceDay] and [referenceNight] are the reference desktop client's own
/// popup colours (its default and night themes), for a host that wants the
/// reference look exactly and for the package's goldens.
@immutable
final class PointerMenuTokens {
  /// A token group with every colour given.
  const PointerMenuTokens({
    required this.background,
    required this.backgroundOver,
    required this.text,
    required this.textOver,
    required this.textDisabled,
    required this.hint,
    required this.hintOver,
    required this.separator,
    required this.shadow,
    required this.ripple,
    required this.arrow,
  });

  /// The default mapping of [palette] onto popup fields.
  ///
  /// The panel is the palette's [ChromePalette.surface] and the text its
  /// on-surface colour; the hint is the muted text. The hovered row is the
  /// on-surface colour at 6% over the panel, which is a light grey wash on a
  /// light palette and a lighter wash on a dark one; a disabled row's text is
  /// the on-surface colour at 26%; the ripple is on-surface at 10%.
  factory PointerMenuTokens.fromPalette(ChromePalette palette) {
    final over = Color.alphaBlend(
      palette.onSurface.withValues(alpha: 0.06),
      palette.surface,
    );
    return PointerMenuTokens(
      background: palette.surface,
      backgroundOver: over,
      text: palette.onSurface,
      textOver: palette.onSurface,
      textDisabled: palette.onSurface.withValues(alpha: 0.26),
      hint: palette.onSurfaceMuted,
      hintOver: palette.onSurfaceMuted,
      separator: palette.separator,
      shadow: const Color(0xFF000000),
      ripple: palette.onSurface.withValues(alpha: 0.10),
      arrow: palette.onSurface,
    );
  }

  /// The reference client's default (day) theme: `windowBg`, `windowBgOver`,
  /// `windowFg`, `menuFgDisabled`, `windowSubTextFg`, `menuSeparatorFg`,
  /// `windowBgRipple` and `windowBoldFg`.
  static const PointerMenuTokens referenceDay = PointerMenuTokens(
    background: Color(0xFFFFFFFF),
    backgroundOver: Color(0xFFF1F1F1),
    text: Color(0xFF000000),
    textOver: Color(0xFF000000),
    textDisabled: Color(0xFFCCCCCC),
    hint: Color(0xFF999999),
    hintOver: Color(0xFF919191),
    separator: Color(0xFFF1F1F1),
    shadow: Color(0xFF000000),
    ripple: Color(0xFFE5E5E5),
    arrow: Color(0xFF222222),
  );

  /// The reference client's night theme; see [referenceDay].
  static const PointerMenuTokens referenceNight = PointerMenuTokens(
    background: Color(0xFF17212B),
    backgroundOver: Color(0xFF232E3C),
    text: Color(0xFFF5F5F5),
    textOver: Color(0xFFE9ECF0),
    textDisabled: Color(0xFF3D4E5C),
    hint: Color(0xFF708499),
    hintOver: Color(0xFF7C90A4),
    separator: Color(0xFF232F39),
    shadow: Color(0xFF000000),
    ripple: Color(0xFF24303D),
    arrow: Color(0xFFE9E8E8),
  );

  /// Panel fill and the fill of every row at rest.
  final Color background;

  /// Fill of the highlighted row (the hovered one, or the keyboard's).
  final Color backgroundOver;

  /// Label colour of a row at rest.
  final Color text;

  /// Label colour of the highlighted row.
  final Color textOver;

  /// Label and hint colour of a row that cannot be chosen.
  final Color textDisabled;

  /// Shortcut hint colour at rest.
  final Color hint;

  /// Shortcut hint colour on the highlighted row.
  final Color hintOver;

  /// The line of a separator.
  final Color separator;

  /// The colour of the panel's shadow; its strength is a metric.
  final Color shadow;

  /// The press ripple.
  final Color ripple;

  /// The submenu arrow.
  final Color arrow;

  /// A copy with the named fields replaced.
  PointerMenuTokens copyWith({
    Color? background,
    Color? backgroundOver,
    Color? text,
    Color? textOver,
    Color? textDisabled,
    Color? hint,
    Color? hintOver,
    Color? separator,
    Color? shadow,
    Color? ripple,
    Color? arrow,
  }) => PointerMenuTokens(
    background: background ?? this.background,
    backgroundOver: backgroundOver ?? this.backgroundOver,
    text: text ?? this.text,
    textOver: textOver ?? this.textOver,
    textDisabled: textDisabled ?? this.textDisabled,
    hint: hint ?? this.hint,
    hintOver: hintOver ?? this.hintOver,
    separator: separator ?? this.separator,
    shadow: shadow ?? this.shadow,
    ripple: ripple ?? this.ripple,
    arrow: arrow ?? this.arrow,
  );

  /// Interpolates every field between [a] and [b].
  // Flutter's `T.lerp(a, b, t)` shape; a constructor cannot take two sources.
  // ignore: prefer_constructors_over_static_methods
  static PointerMenuTokens lerp(
    PointerMenuTokens a,
    PointerMenuTokens b,
    double t,
  ) => PointerMenuTokens(
    background: Color.lerp(a.background, b.background, t)!,
    backgroundOver: Color.lerp(a.backgroundOver, b.backgroundOver, t)!,
    text: Color.lerp(a.text, b.text, t)!,
    textOver: Color.lerp(a.textOver, b.textOver, t)!,
    textDisabled: Color.lerp(a.textDisabled, b.textDisabled, t)!,
    hint: Color.lerp(a.hint, b.hint, t)!,
    hintOver: Color.lerp(a.hintOver, b.hintOver, t)!,
    separator: Color.lerp(a.separator, b.separator, t)!,
    shadow: Color.lerp(a.shadow, b.shadow, t)!,
    ripple: Color.lerp(a.ripple, b.ripple, t)!,
    arrow: Color.lerp(a.arrow, b.arrow, t)!,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PointerMenuTokens &&
          background == other.background &&
          backgroundOver == other.backgroundOver &&
          text == other.text &&
          textOver == other.textOver &&
          textDisabled == other.textDisabled &&
          hint == other.hint &&
          hintOver == other.hintOver &&
          separator == other.separator &&
          shadow == other.shadow &&
          ripple == other.ripple &&
          arrow == other.arrow;

  @override
  int get hashCode => Object.hash(
    background,
    backgroundOver,
    text,
    textOver,
    textDisabled,
    hint,
    hintOver,
    separator,
    shadow,
    ripple,
    arrow,
  );

  @override
  String toString() => 'PointerMenuTokens(background: $background)';
}
