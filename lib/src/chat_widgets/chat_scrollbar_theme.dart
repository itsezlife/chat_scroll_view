import 'package:flutter/material.dart';

/// Scrollbar colours registered as a [ThemeExtension].
///
/// Resolution order: [resolve], then [mergeTheme] fallback from ambient [ThemeData]
/// brightness. Per-screen overrides use a nested `Theme` with
/// `copyWith(extensions: […])`.
///
/// Colours only: sizes belong to the scrollbar painter, behavior to the
/// scrollbar preset.
@immutable
class ChatScrollbarThemeData extends ThemeExtension<ChatScrollbarThemeData> {
  /// Creates scrollbar theme colours for thumb and uniform track.
  const ChatScrollbarThemeData({
    this.thumbColor = const Color(0x66000000),
    this.thumbDraggingColor = const Color(0x99000000),
    this.trackColor = const Color(0x1A000000),
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

  /// Derives scrollbar colours from [theme] when no extension is registered.
  factory ChatScrollbarThemeData.mergeTheme(
    ThemeData theme, {
    Color? thumbColor,
    Color? thumbDraggingColor,
    Color? trackColor,
  }) {
    final base = theme.brightness == Brightness.dark ? dark : light;
    return ChatScrollbarThemeData(
      thumbColor: thumbColor ?? base.thumbColor,
      thumbDraggingColor: thumbDraggingColor ?? base.thumbDraggingColor,
      trackColor: trackColor ?? base.trackColor,
    );
  }

  /// Default colours for light surfaces.
  static const light = ChatScrollbarThemeData();

  /// Default colours for dark surfaces.
  static const dark = ChatScrollbarThemeData(
    thumbColor: Color(0x66FFFFFF),
    thumbDraggingColor: Color(0x99FFFFFF),
    trackColor: Color(0x1AFFFFFF),
  );

  /// Idle thumb fill on the track.
  final Color thumbColor;

  /// Thumb fill while the user is dragging.
  final Color thumbDraggingColor;

  /// Uniform track fill for the full track height.
  final Color trackColor;

  @override
  ChatScrollbarThemeData copyWith({
    Color? thumbColor,
    Color? thumbDraggingColor,
    Color? trackColor,
  }) => ChatScrollbarThemeData(
    thumbColor: thumbColor ?? this.thumbColor,
    thumbDraggingColor: thumbDraggingColor ?? this.thumbDraggingColor,
    trackColor: trackColor ?? this.trackColor,
  );

  @override
  ChatScrollbarThemeData lerp(
    covariant ChatScrollbarThemeData? other,
    double t,
  ) {
    if (other == null) return this;
    return ChatScrollbarThemeData(
      thumbColor: Color.lerp(thumbColor, other.thumbColor, t)!,
      thumbDraggingColor: Color.lerp(
        thumbDraggingColor,
        other.thumbDraggingColor,
        t,
      )!,
      trackColor: Color.lerp(trackColor, other.trackColor, t)!,
    );
  }
}
