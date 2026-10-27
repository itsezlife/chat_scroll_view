import 'package:flutter/material.dart';

/// Scrollbar colours registered as a [ThemeExtension].
///
/// Resolution order: [resolve], then [mergeTheme] fallback from ambient [ThemeData]
/// brightness. Per-screen overrides use a nested `Theme` with
/// `copyWith(extensions: […])`.
///
/// Colours only: sizes belong to the scrollbar painter, behavior to the
/// scrollbar preset. Each part has an idle colour and an engaged one: the
/// track turns [trackHoverColor] while a pointer hovers or grabs the
/// scrollbar, and the thumb runs [thumbColor] → [thumbHoverColor] under a
/// hover → [thumbDraggingColor] under a grab. A painter blends between them
/// by the frame's hover and grab factors, which ease rather than switch, so
/// intermediate colours are part of the look.
@immutable
class ChatScrollbarThemeData extends ThemeExtension<ChatScrollbarThemeData> {
  /// Creates scrollbar theme colours; the defaults are [light].
  const ChatScrollbarThemeData({
    this.thumbColor = const Color(0x66000000),
    this.thumbHoverColor = const Color(0x80000000),
    this.thumbDraggingColor = const Color(0x99000000),
    this.trackColor = const Color(0x1A000000),
    this.trackHoverColor = const Color(0x2C000000),
  });

  /// Resolves scrollbar theme from [context].
  ///
  /// Uses `Theme.of(context).extension<ChatScrollbarThemeData>()` when
  /// registered; otherwise [mergeTheme] from ambient [ThemeData] brightness.
  factory ChatScrollbarThemeData.resolve(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<ChatScrollbarThemeData>() ??
        ChatScrollbarThemeData.mergeTheme(theme);
  }

  /// Derives scrollbar colours from [theme] when no extension is registered:
  /// [light] or [dark] by brightness, with any given colour replacing the
  /// base's.
  factory ChatScrollbarThemeData.mergeTheme(
    ThemeData theme, {
    Color? thumbColor,
    Color? thumbHoverColor,
    Color? thumbDraggingColor,
    Color? trackColor,
    Color? trackHoverColor,
  }) {
    final base = theme.brightness == Brightness.dark ? dark : light;
    return base.copyWith(
      thumbColor: thumbColor,
      thumbHoverColor: thumbHoverColor,
      thumbDraggingColor: thumbDraggingColor,
      trackColor: trackColor,
      trackHoverColor: trackHoverColor,
    );
  }

  /// Default colours for light surfaces: black at 40 % idle, 50 % hovered,
  /// 60 % dragging for the thumb; 10 % idle and 17 % engaged for the track.
  static const light = ChatScrollbarThemeData();

  /// Default colours for dark surfaces: [light]'s alphas in white.
  static const dark = ChatScrollbarThemeData(
    thumbColor: Color(0x66FFFFFF),
    thumbHoverColor: Color(0x80FFFFFF),
    thumbDraggingColor: Color(0x99FFFFFF),
    trackColor: Color(0x1AFFFFFF),
    trackHoverColor: Color(0x2CFFFFFF),
  );

  /// Idle thumb fill on the track.
  final Color thumbColor;

  /// Thumb fill while a mouse or trackpad pointer hovers the scrollbar.
  final Color thumbHoverColor;

  /// Thumb fill while a pointer grabs the scrollbar; wins over
  /// [thumbHoverColor] when both apply.
  final Color thumbDraggingColor;

  /// Uniform track fill for the full track height.
  final Color trackColor;

  /// Track fill while a pointer hovers or grabs the scrollbar.
  final Color trackHoverColor;

  @override
  ChatScrollbarThemeData copyWith({
    Color? thumbColor,
    Color? thumbHoverColor,
    Color? thumbDraggingColor,
    Color? trackColor,
    Color? trackHoverColor,
  }) => ChatScrollbarThemeData(
    thumbColor: thumbColor ?? this.thumbColor,
    thumbHoverColor: thumbHoverColor ?? this.thumbHoverColor,
    thumbDraggingColor: thumbDraggingColor ?? this.thumbDraggingColor,
    trackColor: trackColor ?? this.trackColor,
    trackHoverColor: trackHoverColor ?? this.trackHoverColor,
  );

  @override
  ChatScrollbarThemeData lerp(
    covariant ChatScrollbarThemeData? other,
    double t,
  ) {
    if (other == null) return this;
    return ChatScrollbarThemeData(
      thumbColor: Color.lerp(thumbColor, other.thumbColor, t)!,
      thumbHoverColor: Color.lerp(thumbHoverColor, other.thumbHoverColor, t)!,
      thumbDraggingColor: Color.lerp(
        thumbDraggingColor,
        other.thumbDraggingColor,
        t,
      )!,
      trackColor: Color.lerp(trackColor, other.trackColor, t)!,
      trackHoverColor: Color.lerp(trackHoverColor, other.trackHoverColor, t)!,
    );
  }
}
