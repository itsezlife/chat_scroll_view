import 'dart:ui';

import 'package:flutter/material.dart';

/// Visual tokens for the package message-menu chrome.
///
/// Session, placement, back, and IME stay package-owned. This extension
/// restyles scrim / card / rows. Swap structure with
/// `showChatMessageMenu(menuBuilder: …)` or per-row builders.
///
/// Resolution: [resolve] from `ThemeData.extensions`, then [fromScheme]
/// for omitted colours.
@immutable
class ChatMessageMenuThemeData
    extends ThemeExtension<ChatMessageMenuThemeData> {
  /// Creates (optionally partial) menu tokens.
  const ChatMessageMenuThemeData({
    this.scrimColor,
    this.holeRadius,
    this.cardColor,
    this.cardRadius,
    this.cardShadow,
    this.destructiveColor,
    this.dividerColor,
    this.actionLabelStyle,
    this.actionIconSize,
    this.actionTileHeight,
    this.reactionsColor,
    this.reactionsRadius,
  });

  /// Resolves from [context], filling colours from [ColorScheme] when omitted.
  factory ChatMessageMenuThemeData.resolve(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fromTheme = Theme.of(context).extension<ChatMessageMenuThemeData>();
    return ChatMessageMenuThemeData.fromScheme(scheme).merge(fromTheme);
  }

  /// Package defaults derived from [scheme].
  factory ChatMessageMenuThemeData.fromScheme(ColorScheme scheme) {
    final fill = Color.alphaBlend(
      scheme.onSurface.withValues(alpha: 0.08),
      scheme.surface,
    );
    return ChatMessageMenuThemeData(
      scrimColor: const Color.fromRGBO(0, 0, 0, 0.2),
      holeRadius: 16,
      cardColor: fill,
      cardRadius: 12,
      cardShadow: const <BoxShadow>[
        BoxShadow(
          color: Color.fromRGBO(0, 0, 0, 0.35),
          blurRadius: 12,
          offset: Offset(0, 4),
        ),
      ],
      destructiveColor: scheme.error,
      dividerColor: scheme.outlineVariant.withValues(alpha: 0.45),
      actionIconSize: 24,
      actionTileHeight: 48,
      reactionsColor: fill,
    );
  }

  /// Dim colour at full progress. Alpha is scaled by enter/leave progress.
  final Color? scrimColor;

  /// Corner radius of the undimmed hole over the captured slot.
  final double? holeRadius;

  /// Action-card fill. Null → blended [ColorScheme.surface].
  final Color? cardColor;

  /// Action-card corner radius.
  final double? cardRadius;

  /// Action-card drop shadow.
  final List<BoxShadow>? cardShadow;

  /// Destructive row colour. Null → [ColorScheme.error].
  final Color? destructiveColor;

  /// Divider between normal and destructive rows.
  final Color? dividerColor;

  /// Action label style. Null → `labelLarge` at 16px.
  final TextStyle? actionLabelStyle;

  /// Leading action icon size.
  final double? actionIconSize;

  /// Action row height.
  final double? actionTileHeight;

  /// Reactions-pill fill. Null → same blend as [cardColor].
  final Color? reactionsColor;

  /// Reactions-pill corner radius. Null → half of the strip height.
  final double? reactionsRadius;

  /// Overlay of [other] onto this. Null fields on [other] keep this value.
  ChatMessageMenuThemeData merge(ChatMessageMenuThemeData? other) {
    if (other == null) return this;
    return copyWith(
      scrimColor: other.scrimColor,
      holeRadius: other.holeRadius,
      cardColor: other.cardColor,
      cardRadius: other.cardRadius,
      cardShadow: other.cardShadow,
      destructiveColor: other.destructiveColor,
      dividerColor: other.dividerColor,
      actionLabelStyle: other.actionLabelStyle,
      actionIconSize: other.actionIconSize,
      actionTileHeight: other.actionTileHeight,
      reactionsColor: other.reactionsColor,
      reactionsRadius: other.reactionsRadius,
    );
  }

  @override
  ChatMessageMenuThemeData copyWith({
    Color? scrimColor,
    double? holeRadius,
    Color? cardColor,
    double? cardRadius,
    List<BoxShadow>? cardShadow,
    Color? destructiveColor,
    Color? dividerColor,
    TextStyle? actionLabelStyle,
    double? actionIconSize,
    double? actionTileHeight,
    Color? reactionsColor,
    double? reactionsRadius,
  }) => ChatMessageMenuThemeData(
    scrimColor: scrimColor ?? this.scrimColor,
    holeRadius: holeRadius ?? this.holeRadius,
    cardColor: cardColor ?? this.cardColor,
    cardRadius: cardRadius ?? this.cardRadius,
    cardShadow: cardShadow ?? this.cardShadow,
    destructiveColor: destructiveColor ?? this.destructiveColor,
    dividerColor: dividerColor ?? this.dividerColor,
    actionLabelStyle: actionLabelStyle ?? this.actionLabelStyle,
    actionIconSize: actionIconSize ?? this.actionIconSize,
    actionTileHeight: actionTileHeight ?? this.actionTileHeight,
    reactionsColor: reactionsColor ?? this.reactionsColor,
    reactionsRadius: reactionsRadius ?? this.reactionsRadius,
  );

  @override
  ChatMessageMenuThemeData lerp(
    covariant ChatMessageMenuThemeData? other,
    double t,
  ) {
    if (other == null) return this;
    return ChatMessageMenuThemeData(
      scrimColor: Color.lerp(scrimColor, other.scrimColor, t),
      holeRadius: lerpDouble(holeRadius, other.holeRadius, t),
      cardColor: Color.lerp(cardColor, other.cardColor, t),
      cardRadius: lerpDouble(cardRadius, other.cardRadius, t),
      cardShadow: BoxShadow.lerpList(cardShadow, other.cardShadow, t),
      destructiveColor: Color.lerp(destructiveColor, other.destructiveColor, t),
      dividerColor: Color.lerp(dividerColor, other.dividerColor, t),
      actionLabelStyle: TextStyle.lerp(
        actionLabelStyle,
        other.actionLabelStyle,
        t,
      ),
      actionIconSize: lerpDouble(actionIconSize, other.actionIconSize, t),
      actionTileHeight: lerpDouble(actionTileHeight, other.actionTileHeight, t),
      reactionsColor: Color.lerp(reactionsColor, other.reactionsColor, t),
      reactionsRadius: lerpDouble(reactionsRadius, other.reactionsRadius, t),
    );
  }
}
