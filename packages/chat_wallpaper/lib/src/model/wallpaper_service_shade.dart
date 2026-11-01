/// @docImport 'package:chat_wallpaper/src/widget/chat_wallpaper_surface.dart';
library;

import 'package:chat_wallpaper/src/model/chat_wallpaper.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// Colour matrix that turns the part of a freeform gradient behind a piece of
/// service chrome into that chrome's fill.
///
/// Over a freeform wallpaper, service chrome is filled with the wallpaper's
/// gradient itself — never its pattern — aligned with the wallpaper and
/// passed through this matrix, so each pill is a deeper, more saturated take
/// on exactly the colours around it. The fill is opaque unless [matrixAt]
/// lowers its opacity, and carries white text. Solid and linear wallpapers have no gradient to lend and keep the
/// flat [WallpaperServiceTone].
///
/// ## Formula
///
/// Applied per channel, in order:
///
/// 1. Saturation `s` around the luminance `L = wR·R + wG·G + wB·B`, whose
///    weights are [luminance]: `c ↦ L + s · (c − L)`.
/// 2. Scale: `c ↦ c · scale`.
/// 3. Offset: `c ↦ c + offset · 255`.
///
/// [WallpaperServiceShade.of] shades service chrome around
/// [rec709Luminance]:
///
/// | Pattern | App theme | Saturation | Scale | Offset |
/// |---|---|---|---|---|
/// | none or soft light | light | 1.6 | 0.92 | −0.06 |
/// | none or soft light | dark | 1.6 | 0.97 | +0.12 |
/// | mask | light | 1.1 | 0.8 | −0.06 |
/// | mask | dark | 1.1 | 0.4 | +0.08 |
///
/// A mask shows the gradient only through its shapes on black, so its chrome
/// is darkened much further to sit on that black.
///
/// Other chrome drawn from the same gradient (a fill passed its own
/// [WallpaperServiceFill.shade]) builds its shade from explicit coefficients.
@immutable
final class WallpaperServiceShade {
  /// Shade with explicit coefficients, saturating around [luminance].
  ///
  /// Service chrome takes its shade from [WallpaperServiceShade.of] instead.
  const WallpaperServiceShade({
    required this.saturation,
    required this.scale,
    required this.offset,
    this.luminance = rec709Luminance,
  });

  /// Shade for chrome over [wallpaper] in a light or dark app theme, or `null`
  /// when the wallpaper has no [ChatWallpaper.freeformFill].
  ///
  /// [darkTheme] is the app's theme, not the wallpaper's own brightness.
  static WallpaperServiceShade? of(
    ChatWallpaper wallpaper, {
    required bool darkTheme,
  }) {
    if (wallpaper.freeformFill == null) return null;
    final mask = switch (wallpaper) {
      ChatWallpaper$Patterned(
        pattern: WallpaperPattern(blend: WallpaperPatternBlend.mask),
      ) =>
        true,
      _ => false,
    };
    return switch ((mask, darkTheme)) {
      (false, false) => const WallpaperServiceShade(
        saturation: 1.6,
        scale: 0.92,
        offset: -0.06,
      ),
      (false, true) => const WallpaperServiceShade(
        saturation: 1.6,
        scale: 0.97,
        offset: 0.12,
      ),
      (true, false) => const WallpaperServiceShade(
        saturation: 1.1,
        scale: 0.8,
        offset: -0.06,
      ),
      (true, true) => const WallpaperServiceShade(
        saturation: 1.1,
        scale: 0.4,
        offset: 0.08,
      ),
    };
  }

  /// Rec. 709 luma weights; the grey axis of every [WallpaperServiceShade.of].
  static const WallpaperShadeLuminance rec709Luminance = (
    red: 0.213,
    green: 0.715,
    blue: 0.072,
  );

  /// Haeberli's linear-light weights: more red and blue, less green than
  /// [rec709Luminance], so a strong saturation pushes greens further from
  /// grey than reds and blues.
  static const WallpaperShadeLuminance linearLuminance = (
    red: 0.3086,
    green: 0.6094,
    blue: 0.0820,
  );

  /// Saturation factor: `1` keeps colours, above `1` pushes them from grey.
  final double saturation;

  /// Factor applied to every channel after saturation.
  final double scale;

  /// Added to every channel last, as a fraction of the full channel range.
  final double offset;

  /// Channel weights of the grey that [saturation] pushes colours away from.
  /// They sum to `1`, so a grey input stays grey under any saturation.
  final WallpaperShadeLuminance luminance;

  /// The shade as a 4 × 5 row-major matrix for [ColorFilter.matrix], offsets
  /// in `0 … 255` units. Alpha passes through unchanged.
  List<double> get matrix => matrixAt(1);

  /// [matrix] that also multiplies alpha by [opacity], in `[0, 1]`.
  ///
  /// A layer filtered through it composites as the shade painted at
  /// [opacity]: the colour rows are [matrix]'s, so the shaded colours stay
  /// the same and only how much of what lies behind shows through changes.
  List<double> matrixAt(double opacity) {
    assert(
      opacity >= 0 && opacity <= 1,
      'opacity must be in [0, 1], got $opacity',
    );
    final grey = 1 - saturation;
    final (:red, :green, :blue) = luminance;
    final (r, g, b) = (
      red * grey * scale,
      green * grey * scale,
      blue * grey * scale,
    );
    final s = saturation * scale;
    final shift = offset * 255;
    return [
      r + s, g, b, 0, shift, //
      r, g + s, b, 0, shift,
      r, g, b + s, 0, shift,
      0, 0, 0, opacity, 0,
    ];
  }

  /// [color] through [matrix], opaque, each channel clamped and rounded.
  Color apply(Color color) {
    final m = matrix;
    final (red, green, blue) = (color.r * 255, color.g * 255, color.b * 255);
    int channel(int row) =>
        (m[row * 5] * red +
                m[row * 5 + 1] * green +
                m[row * 5 + 2] * blue +
                m[row * 5 + 4])
            .round()
            .clamp(0, 255);
    return Color.fromARGB(0xFF, channel(0), channel(1), channel(2));
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WallpaperServiceShade &&
          other.saturation == saturation &&
          other.scale == scale &&
          other.offset == offset &&
          other.luminance == luminance;

  @override
  int get hashCode => Object.hash(saturation, scale, offset, luminance);
}

/// Channel weights of a luminance, `L = red·R + green·G + blue·B`.
typedef WallpaperShadeLuminance = ({double red, double green, double blue});
