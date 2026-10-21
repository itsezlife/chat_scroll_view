import 'package:chat_scroll_view/chat_scroll_view.dart'
    show
        ChatEmojiPolicy,
        ChatEmojiPolicy$Android,
        ChatEmojiPolicy$Desktop,
        ChatEmojiPolicy$Ios;
import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/painting.dart';

/// The **service colour** behind the time pill and the headers of an
/// emoji-only message: a translucent colour derived from the chat's wallpaper,
/// so a message without a bubble stays legible over it.
///
/// The wallpaper is a host input: the average colour of what is behind the
/// chat, or null when the host has none (this demo has none). Null takes
/// [defaultWallpaper], so the colour is always the platform's own derivation of
/// a plausible wallpaper, not a fixed black.
///
/// Per platform family:
///
/// - Android darkens the wallpaper in HSV (`s + .05 + .1 (1 - s)`, `v x .65`)
///   at alpha `0x66`; the panels use it as it is, the time pill at 60 % of its
///   alpha.
/// - iOS fills with black at 0.2 over a wallpaper the host gives, and with the
///   built-in wallpaper's `#748391` at 0.45 over none; pill and panels alike.
/// - Desktop's palette is not in the sources at hand: it takes Android's
///   derivation for panels and pill alike (an unverified value, ADR 036).
@immutable
final class EmojiServiceColors {
  const EmojiServiceColors._({
    required this.panel,
    required this.pill,
    required this.text,
  });

  /// The colours of [policy]'s platform family over [wallpaper].
  factory EmojiServiceColors.of(ChatEmojiPolicy policy, {Color? wallpaper}) =>
      switch (policy) {
        ChatEmojiPolicy$Android() => EmojiServiceColors._android(
          wallpaper ?? defaultWallpaper,
        ),
        ChatEmojiPolicy$Ios() => EmojiServiceColors._ios(wallpaper),
        ChatEmojiPolicy$Desktop() => EmojiServiceColors._desktop(
          wallpaper ?? defaultWallpaper,
        ),
      };

  factory EmojiServiceColors._android(Color wallpaper) {
    final panel = _darkened(wallpaper);
    return EmojiServiceColors._(
      panel: panel,
      pill: panel.withValues(alpha: androidAlpha * androidPillShare),
      text: _white,
    );
  }

  factory EmojiServiceColors._ios(Color? wallpaper) {
    final fill = wallpaper == null ? iosBuiltIn : iosOverWallpaper;
    return EmojiServiceColors._(panel: fill, pill: fill, text: _white);
  }

  factory EmojiServiceColors._desktop(Color wallpaper) {
    final panel = _darkened(wallpaper);
    return EmojiServiceColors._(panel: panel, pill: panel, text: _white);
  }

  /// The wallpaper colour a host without one gets: the tint of the built-in
  /// wallpaper of the iOS client, the only neutral wallpaper colour the
  /// sources give.
  static const Color defaultWallpaper = Color(0xFF748391);

  /// Android's alpha for the service colour of a flat wallpaper (`0x66`).
  static const double androidAlpha = 0x66 / 255;

  /// The share of that alpha the time pill is drawn at.
  static const double androidPillShare = 0.6;

  /// iOS's fill over a wallpaper the host gives: black at 0.2.
  static const Color iosOverWallpaper = Color(0x33000000);

  /// iOS's fill with no wallpaper: `#748391` at 0.45.
  static const Color iosBuiltIn = Color(0x73748391);

  /// The fill of the header panels.
  final Color panel;

  /// The fill of the time pill.
  final Color pill;

  /// The colour of the text and the ticks on either.
  final Color text;

  static const Color _white = Color(0xFFFFFFFF);

  /// These colours with [tint] laid over their fills: the selected variant of
  /// the service colour (`msgServiceBgSelected`), which the reference paints
  /// under the time pill of a selected message. The text stays as it is.
  EmojiServiceColors tinted(Color tint) => EmojiServiceColors._(
    panel: Color.alphaBlend(tint, panel),
    pill: Color.alphaBlend(tint, pill),
    text: text,
  );

  static Color _darkened(Color wallpaper) {
    final hsv = HSVColor.fromColor(wallpaper);
    return HSVColor.fromAHSV(
      androidAlpha,
      hsv.hue,
      (hsv.saturation + 0.05 + 0.1 * (1 - hsv.saturation)).clamp(0, 1),
      hsv.value * 0.65,
    ).toColor();
  }

  @override
  bool operator ==(Object other) =>
      other is EmojiServiceColors &&
      other.panel == panel &&
      other.pill == pill &&
      other.text == text;

  @override
  int get hashCode => Object.hash(panel, pill, text);
}
