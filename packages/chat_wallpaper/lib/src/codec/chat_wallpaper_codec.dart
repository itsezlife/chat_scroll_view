import 'dart:convert';

import 'package:chat_wallpaper/src/model/chat_wallpaper.dart';
import 'package:flutter/painting.dart';

/// [ChatWallpaper] ↔ a compact background string.
///
/// ## Grammar
///
/// The string is the part of a background link that follows `bg/`:
///
/// | Kind | Canonical string |
/// |---|---|
/// | [ChatWallpaper$Solid] | `rrggbb` |
/// | [ChatWallpaper$Linear] | `rrggbb-rrggbb?rotation=N` |
/// | [ChatWallpaper$Freeform] | `rrggbb~rrggbb~rrggbb`, or four colours |
/// | [ChatWallpaper$Patterned] | `slug?intensity=I&bg_color=C`, then `&rotation=N` over a linear fill |
///
/// `rrggbb` is a colour's RGB in hex. `N` is the clockwise rotation in
/// degrees ([WallpaperRotation.degrees]). In the pattern form, `slug` is
/// [WallpaperPattern.slug], `C` is the fill's colours written as in its own
/// form, and `I` is [WallpaperPattern.intensity], negated for
/// [WallpaperPatternBlend.mask].
///
/// ## Encoding
///
/// Canonical: lowercase hex, `-` between linear colours, `~` between
/// freeform colours, the rotation written even at 0°, and pattern parameters
/// in the order `intensity`, `bg_color`, `rotation`. Alpha is dropped, so
/// equal wallpapers encode to equal strings, and wallpapers of opaque
/// colours (the model's expectation) round-trip exactly.
///
/// A slug outside letters, digits, `_` and `-`, an intensity outside
/// `[0, 100]`, or a mask at intensity 0 throws an [ArgumentError] rather
/// than producing a string that would not decode to the same wallpaper.
///
/// ## Decoding
///
/// Lenient about spelling:
///
/// - hex in either case;
/// - `-` and `~` interchangeably, at every colour separator;
/// - a linear fill without a rotation, read as 0°;
/// - any integer rotation, snapped by [WallpaperRotation.fromDegrees];
/// - pattern parameters in any order;
/// - a pattern without `intensity`, read as
///   [WallpaperPattern.defaultIntensity] soft light, and `-0` read as `0`.
///
/// Colours decode opaque. A query holding `intensity` or `bg_color` selects
/// the pattern form; otherwise the text before `?` is the colour form, and
/// its colour count selects the kind: one is solid, two linear, three or
/// four freeform.
///
/// Every other input throws a [FormatException] carrying the input as its
/// source: empty input, a token that isn't six hex digits (including the
/// empty token left by a leading or trailing separator), five or more
/// colours, a non-integer rotation or intensity, an intensity outside
/// `[-100, 100]`, a malformed slug, a pattern without `bg_color`, a
/// parameter that is repeated, empty, unknown or not `key=value`, and a
/// rotation on a solid or freeform fill. That last parameter is rejected
/// rather than ignored, because no canonical string carries it.
final class ChatWallpaperCodec extends Codec<ChatWallpaper, String> {
  /// Creates the wallpaper ↔ canonical string codec.
  const ChatWallpaperCodec();

  @override
  Converter<ChatWallpaper, String> get encoder => const _ChatWallpaperEncoder();

  @override
  Converter<String, ChatWallpaper> get decoder => const _ChatWallpaperDecoder();
}

/// Query parameter names shared by both directions.
abstract final class _Param {
  static const String rotation = 'rotation';
  static const String intensity = 'intensity';
  static const String bgColor = 'bg_color';
}

/// Syntax of [WallpaperPattern.slug]: the characters a background link path
/// segment carries without escaping.
final RegExp _$slug = RegExp(r'^[A-Za-z0-9_-]+$');

/// [_$slug] in words, for errors.
const String _$slugSyntax = 'letters, digits, "_" or "-"';

final class _ChatWallpaperEncoder extends Converter<ChatWallpaper, String> {
  const _ChatWallpaperEncoder();

  @override
  String convert(ChatWallpaper input) => switch (input) {
    final ChatWallpaper$ColorFill fill =>
      '${_colors(fill)}${_rotation(fill, separator: '?')}',
    ChatWallpaper$Patterned(:final fill, :final pattern) =>
      '${_slug(pattern.slug)}?${_Param.intensity}=${_signedIntensity(pattern)}'
          '&${_Param.bgColor}=${_colors(fill)}${_rotation(fill, separator: '&')}',
  };

  static String _colors(ChatWallpaper$ColorFill fill) => switch (fill) {
    ChatWallpaper$Solid(:final color) => _hex(color),
    ChatWallpaper$Linear(:final top, :final bottom) =>
      '${_hex(top)}-${_hex(bottom)}',
    ChatWallpaper$Freeform(:final colors) => colors.map(_hex).join('~'),
  };

  /// The rotation parameter, introduced by [separator]; empty for fills
  /// without one.
  static String _rotation(
    ChatWallpaper$ColorFill fill, {
    required String separator,
  }) => switch (fill) {
    ChatWallpaper$Linear(:final rotation) =>
      '$separator${_Param.rotation}=${rotation.degrees}',
    ChatWallpaper$Solid() || ChatWallpaper$Freeform() => '',
  };

  /// The intensity with its sign carrying the blend. Rechecks the model's
  /// debug-only asserts, since an out-of-range or zero mask intensity would
  /// not decode back to the same wallpaper.
  static int _signedIntensity(WallpaperPattern pattern) =>
      switch ((pattern.blend, pattern.intensity)) {
        (_, < 0 || > 100) => throw ArgumentError.value(
          pattern.intensity,
          'intensity',
          'Expected 0 to 100',
        ),
        (WallpaperPatternBlend.mask, 0) => throw ArgumentError.value(
          0,
          'intensity',
          'A mask needs a positive intensity',
        ),
        (WallpaperPatternBlend.softLight, final intensity) => intensity,
        (WallpaperPatternBlend.mask, final intensity) => -intensity,
      };

  static String _slug(String slug) => _$slug.hasMatch(slug)
      ? slug
      : throw ArgumentError.value(slug, 'slug', 'Expected ${_$slugSyntax}');

  static String _hex(Color color) =>
      (color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0');
}

final class _ChatWallpaperDecoder extends Converter<String, ChatWallpaper> {
  const _ChatWallpaperDecoder();

  static final RegExp _separator = RegExp('[-~]');
  static final RegExp _hexColor = RegExp(r'^[0-9a-fA-F]{6}$');
  static final RegExp _parameter = RegExp(r'^([a-z_]+)=(.*)$');
  static final RegExp _integer = RegExp(r'^-?\d+$');

  static const Set<String> _colorFormParams = {_Param.rotation};
  static const Set<String> _patternFormParams = {
    _Param.intensity,
    _Param.bgColor,
    _Param.rotation,
  };

  @override
  ChatWallpaper convert(String input) {
    final (path, query) = switch (input.indexOf('?')) {
      -1 => (input, null),
      final start => (input.substring(0, start), input.substring(start + 1)),
    };
    final params = switch (query) {
      final query? => _params(query, input),
      null => const <String, String>{},
    };
    if (params.containsKey(_Param.intensity) ||
        params.containsKey(_Param.bgColor)) {
      return _patterned(path, params, input);
    }
    _expectOnly(_colorFormParams, params, input);
    return _fill(path, params[_Param.rotation], input);
  }

  static ChatWallpaper$Patterned _patterned(
    String slug,
    Map<String, String> params,
    String source,
  ) {
    _expectOnly(_patternFormParams, params, source);
    if (!_$slug.hasMatch(slug)) {
      throw FormatException(
        'Expected a slug of ${_$slugSyntax}, got "$slug"',
        source,
      );
    }
    final colors = switch (params[_Param.bgColor]) {
      final colors? => colors,
      null => throw FormatException(
        'A pattern needs ${_Param.bgColor}',
        source,
      ),
    };
    final intensity = switch (params[_Param.intensity]) {
      final value? => _intensity(value, source),
      null => WallpaperPattern.defaultIntensity,
    };
    final pattern = switch (intensity) {
      < 0 => WallpaperPattern(
        slug,
        intensity: -intensity,
        blend: WallpaperPatternBlend.mask,
      ),
      _ => WallpaperPattern(slug, intensity: intensity),
    };
    return ChatWallpaper$Patterned(
      _fill(colors, params[_Param.rotation], source),
      pattern,
    );
  }

  /// Parses separated colour [tokens] into the fill their count selects,
  /// oriented by [rotation] when there are two.
  static ChatWallpaper$ColorFill _fill(
    String tokens,
    String? rotation,
    String source,
  ) {
    final colors = [
      for (final token in tokens.split(_separator)) _color(token, source),
    ];
    if (rotation != null && colors.length != 2) {
      throw FormatException('Only a two-colour fill takes a rotation', source);
    }
    return switch (colors) {
      [final color] => ChatWallpaper$Solid(color),
      [final top, final bottom] => ChatWallpaper$Linear(
        top,
        bottom,
        rotation: _rotation(rotation, source),
      ),
      [final color1, final color2, final color3] => ChatWallpaper$Freeform(
        color1,
        color2,
        color3,
      ),
      [final color1, final color2, final color3, final color4] =>
        ChatWallpaper$Freeform(color1, color2, color3, color4),
      _ => throw FormatException(
        'Expected 1 to 4 colours, got ${colors.length}',
        source,
      ),
    };
  }

  /// Splits [query], the text after `?`, into `key=value` pairs.
  static Map<String, String> _params(String query, String source) {
    final params = <String, String>{};
    for (final pair in query.split('&')) {
      final (key, value) = switch (_parameter.firstMatch(pair)) {
        final match? => (match.group(1)!, match.group(2)!),
        null => throw FormatException(
          'Expected key=value, got "$pair"',
          source,
        ),
      };
      if (params.containsKey(key))
        throw FormatException('Repeated parameter "$key"', source);
      params[key] = value;
    }
    return params;
  }

  static void _expectOnly(
    Set<String> allowed,
    Map<String, String> params,
    String source,
  ) {
    for (final key in params.keys) {
      if (!allowed.contains(key))
        throw FormatException('Unexpected parameter "$key"', source);
    }
  }

  /// Parses one `rrggbb` token as an opaque colour.
  ///
  /// The pattern check runs first because [int.parse] alone would also take a
  /// sign or fewer digits.
  static Color _color(String token, String source) {
    if (!_hexColor.hasMatch(token)) {
      throw FormatException(
        'Expected a six-digit hex colour, got "$token"',
        source,
      );
    }
    return Color(0xFF000000 | int.parse(token, radix: 16));
  }

  /// Reads a linear rotation; `null` (no parameter) is 0°.
  static WallpaperRotation _rotation(String? value, String source) {
    if (value == null) return WallpaperRotation.deg0;
    return switch (_integerOrNull(value)) {
      final degrees? => WallpaperRotation.fromDegrees(degrees),
      null => throw FormatException(
        'Expected ${_Param.rotation}=<integer degrees>, got "$value"',
        source,
      ),
    };
  }

  /// Reads a signed pattern intensity in `[-100, 100]`.
  static int _intensity(String value, String source) => switch (_integerOrNull(
    value,
  )) {
    final intensity? when intensity >= -100 && intensity <= 100 => intensity,
    _ => throw FormatException(
      'Expected ${_Param.intensity}=<integer in [-100, 100]>, got "$value"',
      source,
    ),
  };

  /// [value] as an integer when it is only an optional `-` and digits that
  /// fit an [int].
  static int? _integerOrNull(String value) =>
      _integer.hasMatch(value) ? int.tryParse(value) : null;
}
