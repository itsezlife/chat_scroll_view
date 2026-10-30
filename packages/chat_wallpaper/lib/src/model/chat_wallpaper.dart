import 'package:chat_wallpaper/src/model/wallpaper_service_tone.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// Clockwise rotation of a [ChatWallpaper.linear] gradient.
///
/// At [deg0] the first colour sits at the top and the second at the bottom;
/// each step turns that axis 45° clockwise. Diagonals run corner to corner.
enum WallpaperRotation {
  /// First colour at the top.
  deg0(0),

  /// First colour at the top-right corner.
  deg45(45),

  /// First colour on the right.
  deg90(90),

  /// First colour at the bottom-right corner.
  deg135(135),

  /// First colour at the bottom.
  deg180(180),

  /// First colour at the bottom-left corner.
  deg225(225),

  /// First colour on the left.
  deg270(270),

  /// First colour at the top-left corner.
  deg315(315);

  const WallpaperRotation(this.degrees);

  /// Snaps any angle to the nearest 45° step in `[0, 360)`.
  factory WallpaperRotation.fromDegrees(int degrees) =>
      values[(degrees / 45).round() % values.length];

  /// Angle in degrees, one of 0, 45, …, 315.
  final int degrees;
}

/// How a [WallpaperPattern] combines with the colour fill under it.
enum WallpaperPatternBlend {
  /// The pattern tints the fill with the soft-light blend, in black on a
  /// light fill and white on a dark one. Suited to light themes.
  softLight,

  /// The fill shows only through the pattern's shapes, on black. Suited to
  /// dark themes.
  mask,
}

/// A monochrome pattern drawn over a colour fill.
///
/// The pattern is identified by [slug]; the artwork behind it is resolved
/// at paint time, so a value never holds image data. A slug with no
/// artwork paints the fill alone.
@immutable
final class WallpaperPattern extends Equatable {
  /// Creates a pattern drawn at [intensity] percent with [blend].
  ///
  /// [intensity] is in `[0, 100]`, and at least `1` for
  /// [WallpaperPatternBlend.mask]: a zero-intensity mask paints plain black,
  /// and has no string form in `ChatWallpaperCodec`, which carries the mask
  /// blend as a negative intensity.
  const WallpaperPattern(
    this.slug, {
    this.intensity = defaultIntensity,
    this.blend = WallpaperPatternBlend.softLight,
  }) : assert(
         intensity >= 0 && intensity <= 100,
         'intensity must be in [0, 100], got $intensity',
       ),
       assert(
         blend != WallpaperPatternBlend.mask || intensity > 0,
         'a mask pattern needs an intensity of at least 1',
       );

  /// Intensity a pattern gets when none is given, here and in decoded
  /// strings that omit it.
  static const int defaultIntensity = 50;

  /// Identity of the artwork: letters, digits, `_` and `-`. One slug names
  /// one artwork everywhere, since it is persisted and compared.
  final String slug;

  /// Strength of the pattern in whole percent, `0` … `100`.
  ///
  /// Whole percent rather than a fraction, so every value has exactly one
  /// string form and a decoded pattern equals the one encoded.
  final int intensity;

  /// How the pattern combines with the fill.
  final WallpaperPatternBlend blend;

  /// [intensity] as an opacity in `[0, 1]`.
  double get opacity => intensity / 100;

  @override
  List<Object?> get props => [slug, intensity, blend];
}

/// What a chat draws behind its messages.
///
/// A value: equal wallpapers render equal pixels. Colours are expected
/// opaque — [averageColor] and the renderer ignore alpha.
///
/// Kinds form two levels: [ChatWallpaper$ColorFill] groups the plain fills
/// (solid, linear, freeform), and [ChatWallpaper$Patterned] draws a
/// [WallpaperPattern] over exactly one of them.
@immutable
sealed class ChatWallpaper extends Equatable {
  const ChatWallpaper();

  /// One flat colour.
  const factory ChatWallpaper.solid(Color color) = ChatWallpaper$Solid;

  /// Two-colour linear gradient oriented by [WallpaperRotation].
  const factory ChatWallpaper.linear(
    Color top,
    Color bottom, {
    WallpaperRotation rotation,
  }) = ChatWallpaper$Linear;

  /// Three- or four-point freeform gradient: colour points on a ring,
  /// smoothly mixed across the whole surface.
  const factory ChatWallpaper.freeform(
    Color color1,
    Color color2,
    Color color3, [
    Color? color4,
  ]) = ChatWallpaper$Freeform;

  /// [pattern] drawn over [fill].
  const factory ChatWallpaper.patterned(
    ChatWallpaper$ColorFill fill,
    WallpaperPattern pattern,
  ) = ChatWallpaper$Patterned;

  /// Brightness ([HSVColor.value]) of [averageColor] under which the
  /// wallpaper counts as dark.
  static const double darkValueThreshold = 0.3;

  /// Fill colours in declaration order.
  List<Color> get colors;

  /// Running pairwise average of [colors], always opaque.
  ///
  /// Each step halves both channels before adding, so later colours weigh
  /// more (four colours: 1/8, 1/8, 1/4, 1/2). The integer halving is part of
  /// the contract: [isDark] and [serviceTone] are defined on these exact
  /// bytes.
  Color get averageColor =>
      colors.skip(1).fold(_opaque(colors.first), _average);

  /// Whether the wallpaper is dark enough to carry light content.
  bool get isDark =>
      HSVColor.fromColor(averageColor).value < darkValueThreshold;

  /// Colours for service chrome drawn on this wallpaper, projected from
  /// [averageColor] with the same formula for every fill kind.
  WallpaperServiceTone get serviceTone =>
      WallpaperServiceTone.fromColor(averageColor);

  /// The freeform fill under any pattern, or `null` for solid and linear
  /// fills: the only fill with colour points to move and a gradient to lend
  /// service chrome.
  ChatWallpaper$Freeform? get freeformFill => switch (this) {
    final ChatWallpaper$Freeform freeform => freeform,
    ChatWallpaper$Solid() || ChatWallpaper$Linear() => null,
    ChatWallpaper$Patterned(:final fill) => fill.freeformFill,
  };

  /// This wallpaper with its pattern shapes taken away: what content fading
  /// into the wallpaper should dissolve into, so shapes are never drawn over
  /// the content. A soft-light pattern leaves its fill; a mask leaves black,
  /// since its fill shows only through the shapes. Unpatterned wallpapers are
  /// returned as they are.
  ChatWallpaper get withoutPattern => switch (this) {
    ChatWallpaper$Patterned(
      :final fill,
      pattern: WallpaperPattern(blend: WallpaperPatternBlend.softLight),
    ) =>
      fill,
    ChatWallpaper$Patterned(
      pattern: WallpaperPattern(blend: WallpaperPatternBlend.mask),
    ) =>
      const ChatWallpaper.solid(Color(0xFF000000)),
    ChatWallpaper$ColorFill() => this,
  };

  static Color _opaque(Color color) => Color(color.toARGB32() | 0xFF000000);

  static Color _average(Color a, Color b) {
    final x = a.toARGB32();
    final y = b.toARGB32();
    int half(int shift) =>
        ((x >> shift) & 0xFF) ~/ 2 + ((y >> shift) & 0xFF) ~/ 2;
    return Color.fromARGB(0xFF, half(16), half(8), half(0));
  }
}

/// A plain colour fill: the kinds a [WallpaperPattern] can be drawn over.
sealed class ChatWallpaper$ColorFill extends ChatWallpaper {
  const ChatWallpaper$ColorFill();
}

/// See [ChatWallpaper.solid].
final class ChatWallpaper$Solid extends ChatWallpaper$ColorFill {
  /// Creates a flat [color] wallpaper.
  const ChatWallpaper$Solid(this.color);

  /// Fill colour.
  final Color color;

  @override
  List<Color> get colors => [color];

  @override
  List<Object?> get props => [color];
}

/// See [ChatWallpaper.linear].
final class ChatWallpaper$Linear extends ChatWallpaper$ColorFill {
  /// Creates a [top] → [bottom] gradient turned by [rotation].
  const ChatWallpaper$Linear(
    this.top,
    this.bottom, {
    this.rotation = WallpaperRotation.deg0,
  });

  /// Colour at the start of the axis (the top at [WallpaperRotation.deg0]).
  final Color top;

  /// Colour at the end of the axis (the bottom at [WallpaperRotation.deg0]).
  final Color bottom;

  /// Axis orientation.
  final WallpaperRotation rotation;

  @override
  List<Color> get colors => [top, bottom];

  @override
  List<Object?> get props => [top, bottom, rotation];
}

/// See [ChatWallpaper.freeform].
final class ChatWallpaper$Freeform extends ChatWallpaper$ColorFill {
  /// Creates a three-point gradient, or four-point when [color4] is set.
  const ChatWallpaper$Freeform(
    this.color1,
    this.color2,
    this.color3, [
    this.color4,
  ]);

  /// First colour point.
  final Color color1;

  /// Second colour point.
  final Color color2;

  /// Third colour point.
  final Color color3;

  /// Optional fourth colour point.
  final Color? color4;

  @override
  List<Color> get colors => [color1, color2, color3, ?color4];

  @override
  List<Object?> get props => [color1, color2, color3, color4];
}

/// See [ChatWallpaper.patterned].
///
/// Colour-derived facts ([colors], [averageColor], [isDark], [serviceTone])
/// are the [fill]'s: the pattern is monochrome and does not shift them.
final class ChatWallpaper$Patterned extends ChatWallpaper {
  /// Creates [pattern] drawn over [fill].
  const ChatWallpaper$Patterned(this.fill, this.pattern);

  /// Colour fill under the pattern.
  final ChatWallpaper$ColorFill fill;

  /// Pattern drawn over [fill].
  final WallpaperPattern pattern;

  @override
  List<Color> get colors => fill.colors;

  @override
  List<Object?> get props => [fill, pattern];
}
