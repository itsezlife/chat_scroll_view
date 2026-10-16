import 'dart:ui' show Color;

import 'package:chrome_foundation/src/palette/chrome_palette.dart';
import 'package:meta/meta.dart';

/// Colours of the composer: the input island, its reply preview and the fade
/// under it.
///
/// Derived from a [ChromePalette] by [ComposerTokens.fromPalette]; a host
/// overrides single fields with [copyWith] or supplies the whole group to a
/// `ChromeThemeScope`.
@immutable
final class ComposerTokens {
  /// A composer token group with every colour given.
  const ComposerTokens({
    required this.background,
    required this.text,
    required this.cursor,
    required this.shadow,
    required this.replyLine,
    required this.replyName,
    required this.replyText,
    required this.contentFade,
  });

  /// The default mapping of [palette] roles onto composer fields.
  factory ComposerTokens.fromPalette(ChromePalette palette) => ComposerTokens(
    background: palette.surface,
    text: palette.onSurface,
    cursor: palette.accent,
    shadow: palette.shadow,
    replyLine: palette.accent,
    replyName: palette.accent,
    replyText: palette.onSurfaceMuted,
    contentFade: palette.contentFade,
  );

  /// Composer fill.
  final Color background;

  /// Input text.
  final Color text;

  /// Text cursor.
  final Color cursor;

  /// Composer shadow ink.
  final Color shadow;

  /// Reply preview accent line.
  final Color replyLine;

  /// Reply preview author name.
  final Color replyName;

  /// Reply preview body.
  final Color replyText;

  /// Fill under the composer and the panel standing in for blurred wallpaper.
  ///
  /// Must differ from the panel background, or the sheet's top edge and the
  /// island-to-panel gap stop reading.
  final Color contentFade;

  /// A copy with the named fields replaced.
  ComposerTokens copyWith({
    Color? background,
    Color? text,
    Color? cursor,
    Color? shadow,
    Color? replyLine,
    Color? replyName,
    Color? replyText,
    Color? contentFade,
  }) => ComposerTokens(
    background: background ?? this.background,
    text: text ?? this.text,
    cursor: cursor ?? this.cursor,
    shadow: shadow ?? this.shadow,
    replyLine: replyLine ?? this.replyLine,
    replyName: replyName ?? this.replyName,
    replyText: replyText ?? this.replyText,
    contentFade: contentFade ?? this.contentFade,
  );

  /// Interpolates every field between [a] and [b].
  // Flutter's `T.lerp(a, b, t)` shape; a constructor cannot take two sources.
  // ignore: prefer_constructors_over_static_methods
  static ComposerTokens lerp(ComposerTokens a, ComposerTokens b, double t) =>
      ComposerTokens(
        background: Color.lerp(a.background, b.background, t)!,
        text: Color.lerp(a.text, b.text, t)!,
        cursor: Color.lerp(a.cursor, b.cursor, t)!,
        shadow: Color.lerp(a.shadow, b.shadow, t)!,
        replyLine: Color.lerp(a.replyLine, b.replyLine, t)!,
        replyName: Color.lerp(a.replyName, b.replyName, t)!,
        replyText: Color.lerp(a.replyText, b.replyText, t)!,
        contentFade: Color.lerp(a.contentFade, b.contentFade, t)!,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ComposerTokens &&
          background == other.background &&
          text == other.text &&
          cursor == other.cursor &&
          shadow == other.shadow &&
          replyLine == other.replyLine &&
          replyName == other.replyName &&
          replyText == other.replyText &&
          contentFade == other.contentFade;

  @override
  int get hashCode => Object.hash(
    background,
    text,
    cursor,
    shadow,
    replyLine,
    replyName,
    replyText,
    contentFade,
  );

  @override
  String toString() => 'ComposerTokens(background: $background)';
}
