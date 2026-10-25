import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// The monospace face the chrome draws code and the Mono label in.
///
/// Flutter passes a family straight to the platform font manager, and only
/// some of them know the CSS generic `'monospace'`: Android's font config and
/// fontconfig on Linux resolve it, CoreText (iOS, macOS) and DirectWrite
/// (Windows) do not, and there a `'monospace'` span silently falls back to
/// the proportional body face. So a system family that ships with the OS is
/// named on exactly those platforms, and the rest keep the generic. Web keeps
/// it too: CanvasKit reaches no system fonts, so only a bundled asset helps
/// there.
///
/// The same mapping as `flutter_md`'s default monospace family, so a code run
/// in the composer and in the sent message look alike.
abstract final class ChromeMonospace {
  /// The primary face for [platform].
  static String familyFor(TargetPlatform platform) {
    if (kIsWeb) return 'monospace';
    return switch (platform) {
      // Ships with every iOS and macOS release.
      TargetPlatform.iOS || TargetPlatform.macOS => 'Menlo',
      // Ships with Windows since Vista.
      TargetPlatform.windows => 'Consolas',
      TargetPlatform.android ||
      TargetPlatform.fuchsia ||
      TargetPlatform.linux => 'monospace',
    };
  }

  /// Faces tried after the primary one, for a platform whose own is missing
  /// (a trimmed Linux image, a custom Android ROM). Ends in the generic, so
  /// anything that resolves it still gets a monospace face.
  static const List<String> fallback = <String>[
    'Menlo',
    'Consolas',
    'DejaVu Sans Mono',
    'Roboto Mono',
    'Courier New',
    'monospace',
  ];

  /// [base] in the monospace face of [platform] (by default the one this app
  /// runs on).
  ///
  /// Built afresh rather than with `copyWith` or `merge`: a base in a host's
  /// bundled font carries that font's package, which both keep, so the face
  /// would resolve as `packages/<package>/monospace` and fall back to the
  /// body face on every platform. Every other property of [base] is kept.
  static TextStyle style(TextStyle base, {TargetPlatform? platform}) =>
      TextStyle(
        inherit: base.inherit,
        color: base.foreground == null ? base.color : null,
        backgroundColor: base.background == null ? base.backgroundColor : null,
        fontSize: base.fontSize,
        fontWeight: base.fontWeight,
        fontStyle: base.fontStyle,
        letterSpacing: base.letterSpacing,
        wordSpacing: base.wordSpacing,
        textBaseline: base.textBaseline,
        height: base.height,
        leadingDistribution: base.leadingDistribution,
        locale: base.locale,
        foreground: base.foreground,
        background: base.background,
        shadows: base.shadows,
        fontFeatures: base.fontFeatures,
        fontVariations: base.fontVariations,
        decoration: base.decoration,
        decorationColor: base.decorationColor,
        decorationStyle: base.decorationStyle,
        decorationThickness: base.decorationThickness,
        debugLabel: base.debugLabel,
        fontFamily: familyFor(platform ?? defaultTargetPlatform),
        fontFamilyFallback: fallback,
        overflow: base.overflow,
      );
}
