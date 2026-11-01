import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// Colours for service chrome drawn straight on a wallpaper — day headers,
/// system message pills, and similar non-bubble labels.
///
/// A translucent, deeper take on the wallpaper's hue carrying white text, so
/// the chrome stays legible on light and dark wallpapers alike while still
/// reading as part of the background.
///
/// ## Formula
///
/// Projected from one opaque source colour (for a wallpaper, its
/// `averageColor`) in HSV:
///
/// | Channel | Result |
/// |---|---|
/// | Hue | unchanged |
/// | Saturation | `s + 0.05 + 0.1 · (1 − s)`, capped at 1 |
/// | Value | `v · 0.65` |
/// | Alpha | `0x66` |
///
/// Colour channels are truncated to 8 bits rather than rounded; the exact
/// bytes are part of the contract.
///
/// [foreground] is always opaque white. The formula is flat: every piece of
/// chrome gets the same tone regardless of where it sits. Over a freeform
/// gradient, a `WallpaperServiceFill` under a `ChatWallpaperSurface` fills
/// chrome with the gradient behind it through a `WallpaperServiceShade`
/// instead; the tone stays the fallback.
@immutable
final class WallpaperServiceTone {
  /// Tone with explicit colours; prefer [WallpaperServiceTone.fromColor].
  const WallpaperServiceTone({
    required this.background,
    required this.foreground,
  });

  /// Projects the tone from [color]; its alpha is ignored.
  factory WallpaperServiceTone.fromColor(Color color) {
    final hsv = HSVColor.fromColor(color.withValues(alpha: 1));
    final s = hsv.saturation;
    return WallpaperServiceTone(
      background: _truncatedRgb(
        hsv.hue,
        (s + _saturationLift + _saturationSpread * (1 - s)).clamp(0, 1),
        hsv.value * _valueScale,
      ).withAlpha(_backgroundAlpha),
      foreground: const Color(0xFFFFFFFF),
    );
  }

  /// Opaque colour for [hue] (degrees), [saturation] and [value], each
  /// channel truncated to 8 bits.
  ///
  /// [HSVColor.toColor] rounds channels instead, which moves a channel one
  /// step up whenever its fraction reaches `.5`.
  static Color _truncatedRgb(double hue, double saturation, double value) {
    final chroma = saturation * value;
    final sector = hue / 60;
    final secondary = chroma * (1 - (sector % 2 - 1).abs());
    final match = value - chroma;
    final (r, g, b) = switch (sector.floor() % 6) {
      0 => (chroma, secondary, 0.0),
      1 => (secondary, chroma, 0.0),
      2 => (0.0, chroma, secondary),
      3 => (0.0, secondary, chroma),
      4 => (secondary, 0.0, chroma),
      _ => (chroma, 0.0, secondary),
    };
    int channel(double c) => ((c + match) * 0xFF).toInt();
    return Color.fromARGB(0xFF, channel(r), channel(g), channel(b));
  }

  /// Flat saturation added to every source.
  static const double _saturationLift = 0.05;

  /// Extra saturation proportional to how unsaturated the source is, so
  /// greys gain the most colour.
  static const double _saturationSpread = 0.1;

  /// Factor applied to the source's HSV value.
  static const double _valueScale = 0.65;

  /// 8-bit alpha of [background].
  static const int _backgroundAlpha = 0x66;

  /// Translucent fill for service chrome.
  final Color background;

  /// Text and icon colour on [background].
  final Color foreground;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WallpaperServiceTone &&
          other.background == background &&
          other.foreground == foreground;

  @override
  int get hashCode => Object.hash(background, foreground);
}
