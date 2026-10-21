import 'dart:ui' show Brightness, Color;

import 'package:flutter/material.dart' show ColorScheme;
import 'package:meta/meta.dart';

/// The **chrome palette**: the small set of semantic colour roles every chrome
/// token group derives from.
///
/// A palette names what a colour is *for* (a surface, text on it, an icon, the
/// accent), never which component paints it: components read their own token
/// group (`ComposerTokens`, `PanelTokens`, ...), and each group's `fromPalette`
/// maps roles to its fields. One palette is therefore the single brightness
/// mechanism for the whole chrome.
///
/// Roles that carry text or icons are chosen so each pairing a token group
/// draws stays at WCAG AA (4.5:1 text, 3:1 icons) in [ChromePalette.light],
/// [ChromePalette.dark] and both high-contrast presets; a custom palette is
/// the host's responsibility, and [ChromeContrast] measures it.
///
/// Translucent roles ([surfaceTint], [separator], dark [onSurfaceMuted]) are
/// drawn over [surfaceDim] or [surface]; measure them composited.
@immutable
final class ChromePalette {
  /// A custom palette: every role is the host's.
  const ChromePalette({
    required this.brightness,
    required this.surface,
    required this.surfaceDim,
    required this.surfaceRaised,
    required this.surfaceSelected,
    required this.surfaceTint,
    required this.onSurface,
    required this.onSurfaceMuted,
    required this.iconIdle,
    required this.iconActive,
    required this.accent,
    required this.onAccent,
    required this.separator,
    required this.destructive,
    required this.contentFade,
    required this.shadow,
  });

  /// The light palette of the reference client, adjusted where the original
  /// greys and blue fell below AA (see the package README for the original
  /// values).
  const ChromePalette.light()
    : brightness = Brightness.light,
      surface = const Color(0xFFFFFFFF),
      surfaceDim = const Color(0xFFF0F2F5),
      surfaceRaised = const Color(0xFFE8EAED),
      surfaceSelected = const Color(0xFFFFFFFF),
      surfaceTint = const Color(0xFFE2E5E7),
      onSurface = const Color(0xFF000000),
      onSurfaceMuted = const Color(0xFF5F666D),
      iconIdle = const Color(0xFF7A8189),
      iconActive = const Color(0xFF5E6976),
      accent = const Color(0xFF2874B0),
      onAccent = const Color(0xFFFFFFFF),
      separator = const Color(0x12000000),
      destructive = const Color(0xFFC62828),
      contentFade = const Color(0xFFFFFFFF),
      shadow = const Color(0xFF000000);

  /// The dark palette of the reference client, adjusted where the original
  /// greys fell below AA (see the package README for the original values).
  const ChromePalette.dark()
    : brightness = Brightness.dark,
      surface = const Color(0xFF20242A),
      surfaceDim = const Color(0xFF20242A),
      surfaceRaised = const Color(0xFF2C2C2E),
      surfaceSelected = const Color(0xFF3A3A3C),
      surfaceTint = const Color(0x0ACDEAFF),
      onSurface = const Color(0xFFFFFFFF),
      onSurfaceMuted = const Color(0x99FFFFFF),
      iconIdle = const Color(0x80FFFFFF),
      iconActive = const Color(0xFFFFFFFF),
      accent = const Color(0xFF54A1DB),
      onAccent = const Color(0xFF20242A),
      separator = const Color(0x1E000000),
      destructive = const Color(0xFFFF6B6B),
      // Soft wallpaper-scrim stand-in: darker than [surfaceDim] for edge
      // contrast, but not pure black (reads as a heavy nav brick).
      contentFade = const Color(0xFF15191E),
      shadow = const Color(0xFF000000);

  /// Light palette with near-black ink (7:1 or better for text and icons),
  /// opaque greys and a visible [separator].
  const ChromePalette.highContrastLight()
    : brightness = Brightness.light,
      surface = const Color(0xFFFFFFFF),
      surfaceDim = const Color(0xFFF2F2F2),
      surfaceRaised = const Color(0xFFE6E6E6),
      surfaceSelected = const Color(0xFFFFFFFF),
      surfaceTint = const Color(0xFFD9D9D9),
      onSurface = const Color(0xFF000000),
      onSurfaceMuted = const Color(0xFF333333),
      iconIdle = const Color(0xFF404040),
      iconActive = const Color(0xFF000000),
      accent = const Color(0xFF0A4A80),
      onAccent = const Color(0xFFFFFFFF),
      separator = const Color(0x99000000),
      destructive = const Color(0xFF9B0000),
      contentFade = const Color(0xFFFFFFFF),
      shadow = const Color(0xFF000000);

  /// Dark palette with white ink (7:1 or better for text and icons), opaque
  /// greys and a visible [separator].
  const ChromePalette.highContrastDark()
    : brightness = Brightness.dark,
      surface = const Color(0xFF000000),
      surfaceDim = const Color(0xFF0A0A0A),
      surfaceRaised = const Color(0xFF1C1C1E),
      surfaceSelected = const Color(0xFF2C2C2E),
      surfaceTint = const Color(0x33FFFFFF),
      onSurface = const Color(0xFFFFFFFF),
      onSurfaceMuted = const Color(0xFFE0E0E0),
      iconIdle = const Color(0xFFD0D0D0),
      iconActive = const Color(0xFFFFFFFF),
      accent = const Color(0xFF7FC1FF),
      onAccent = const Color(0xFF000000),
      separator = const Color(0x99FFFFFF),
      destructive = const Color(0xFFFF8A80),
      contentFade = const Color(0xFF000000),
      shadow = const Color(0xFF000000);

  /// The preset for [brightness]; [highContrast] selects the high-contrast
  /// one.
  factory ChromePalette.forBrightness(
    Brightness brightness, {
    bool highContrast = false,
  }) => switch ((brightness, highContrast)) {
    (Brightness.light, false) => const ChromePalette.light(),
    (Brightness.dark, false) => const ChromePalette.dark(),
    (Brightness.light, true) => const ChromePalette.highContrastLight(),
    (Brightness.dark, true) => const ChromePalette.highContrastDark(),
  };

  /// A palette from a Material [scheme], for hosts that already theme with
  /// `ColorScheme`.
  ///
  /// The chrome has no dependency on `ThemeData`; this is the only bridge.
  /// `surface`, `onSurface`, `primary`, `onPrimary` and `error` map to the
  /// same-named roles; the container surfaces map to [surfaceDim],
  /// [surfaceRaised] and [surfaceSelected]; `onSurfaceVariant` is the muted
  /// text and idle icon colour; `outlineVariant` is the [separator]. Scheme
  /// roles guarantee Material's own contrast, not the chrome's pairings:
  /// measure with [ChromeContrast] if the host cares.
  factory ChromePalette.fromColorScheme(ColorScheme scheme) => ChromePalette(
    brightness: scheme.brightness,
    surface: scheme.surface,
    surfaceDim: scheme.surfaceContainer,
    surfaceRaised: scheme.surfaceContainerHigh,
    surfaceSelected: scheme.surfaceContainerHighest,
    surfaceTint: scheme.onSurface.withValues(alpha: 0.08),
    onSurface: scheme.onSurface,
    onSurfaceMuted: scheme.onSurfaceVariant,
    iconIdle: scheme.onSurfaceVariant,
    iconActive: scheme.onSurface,
    accent: scheme.primary,
    onAccent: scheme.onPrimary,
    separator: scheme.outlineVariant,
    destructive: scheme.error,
    contentFade: scheme.surfaceContainerLowest,
    shadow: scheme.shadow,
  );

  /// Whether the roles are tuned for light or dark content.
  ///
  /// Used where chrome adapts structure (glass stroke, shadow strength), not
  /// to choose colours: those come from the roles.
  final Brightness brightness;

  /// Base chrome fill: the composer.
  final Color surface;

  /// Fill one step off [surface]: the panel body and strips.
  final Color surfaceDim;

  /// Opaque raised fill: floating pills and buttons.
  final Color surfaceRaised;

  /// Fill of the selected segment inside a [surfaceRaised] pill.
  final Color surfaceSelected;

  /// Translucent selection wash, drawn over [surfaceDim].
  final Color surfaceTint;

  /// Primary text and icon colour on every surface.
  final Color onSurface;

  /// Secondary text: hints, captions, section titles, empty states, idle
  /// labels.
  final Color onSurfaceMuted;

  /// Idle icon colour.
  final Color iconIdle;

  /// Selected or pressed icon colour.
  final Color iconActive;

  /// Brand colour: send button, cursor, reply accent, selection underline.
  final Color accent;

  /// Content drawn on [accent].
  final Color onAccent;

  /// Hairline between regions; drawn over [surfaceDim].
  final Color separator;

  /// Destructive action colour.
  final Color destructive;

  /// Fill under the composer and panel that stands in for blurred wallpaper.
  ///
  /// Must differ from [surfaceDim], or the panel's top edge and the gap
  /// between the composer island and the panel disappear.
  final Color contentFade;

  /// Shadow ink.
  final Color shadow;

  /// A copy with the named roles replaced.
  ChromePalette copyWith({
    Brightness? brightness,
    Color? surface,
    Color? surfaceDim,
    Color? surfaceRaised,
    Color? surfaceSelected,
    Color? surfaceTint,
    Color? onSurface,
    Color? onSurfaceMuted,
    Color? iconIdle,
    Color? iconActive,
    Color? accent,
    Color? onAccent,
    Color? separator,
    Color? destructive,
    Color? contentFade,
    Color? shadow,
  }) => ChromePalette(
    brightness: brightness ?? this.brightness,
    surface: surface ?? this.surface,
    surfaceDim: surfaceDim ?? this.surfaceDim,
    surfaceRaised: surfaceRaised ?? this.surfaceRaised,
    surfaceSelected: surfaceSelected ?? this.surfaceSelected,
    surfaceTint: surfaceTint ?? this.surfaceTint,
    onSurface: onSurface ?? this.onSurface,
    onSurfaceMuted: onSurfaceMuted ?? this.onSurfaceMuted,
    iconIdle: iconIdle ?? this.iconIdle,
    iconActive: iconActive ?? this.iconActive,
    accent: accent ?? this.accent,
    onAccent: onAccent ?? this.onAccent,
    separator: separator ?? this.separator,
    destructive: destructive ?? this.destructive,
    contentFade: contentFade ?? this.contentFade,
    shadow: shadow ?? this.shadow,
  );

  /// Interpolates every role between [a] and [b].
  ///
  /// [brightness] is not interpolable: it flips from [a]'s to [b]'s at
  /// `t >= 0.5`.
  // Flutter's `T.lerp(a, b, t)` shape; a constructor cannot take two sources.
  // ignore: prefer_constructors_over_static_methods
  static ChromePalette lerp(ChromePalette a, ChromePalette b, double t) =>
      ChromePalette(
        brightness: t < 0.5 ? a.brightness : b.brightness,
        surface: Color.lerp(a.surface, b.surface, t)!,
        surfaceDim: Color.lerp(a.surfaceDim, b.surfaceDim, t)!,
        surfaceRaised: Color.lerp(a.surfaceRaised, b.surfaceRaised, t)!,
        surfaceSelected: Color.lerp(a.surfaceSelected, b.surfaceSelected, t)!,
        surfaceTint: Color.lerp(a.surfaceTint, b.surfaceTint, t)!,
        onSurface: Color.lerp(a.onSurface, b.onSurface, t)!,
        onSurfaceMuted: Color.lerp(a.onSurfaceMuted, b.onSurfaceMuted, t)!,
        iconIdle: Color.lerp(a.iconIdle, b.iconIdle, t)!,
        iconActive: Color.lerp(a.iconActive, b.iconActive, t)!,
        accent: Color.lerp(a.accent, b.accent, t)!,
        onAccent: Color.lerp(a.onAccent, b.onAccent, t)!,
        separator: Color.lerp(a.separator, b.separator, t)!,
        destructive: Color.lerp(a.destructive, b.destructive, t)!,
        contentFade: Color.lerp(a.contentFade, b.contentFade, t)!,
        shadow: Color.lerp(a.shadow, b.shadow, t)!,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChromePalette &&
          brightness == other.brightness &&
          surface == other.surface &&
          surfaceDim == other.surfaceDim &&
          surfaceRaised == other.surfaceRaised &&
          surfaceSelected == other.surfaceSelected &&
          surfaceTint == other.surfaceTint &&
          onSurface == other.onSurface &&
          onSurfaceMuted == other.onSurfaceMuted &&
          iconIdle == other.iconIdle &&
          iconActive == other.iconActive &&
          accent == other.accent &&
          onAccent == other.onAccent &&
          separator == other.separator &&
          destructive == other.destructive &&
          contentFade == other.contentFade &&
          shadow == other.shadow;

  @override
  int get hashCode => Object.hash(
    brightness,
    surface,
    surfaceDim,
    surfaceRaised,
    surfaceSelected,
    surfaceTint,
    onSurface,
    onSurfaceMuted,
    iconIdle,
    iconActive,
    accent,
    onAccent,
    separator,
    destructive,
    contentFade,
    shadow,
  );

  @override
  String toString() => 'ChromePalette($brightness, accent: $accent)';
}
