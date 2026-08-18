import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Visual tokens for the default selection chrome.
///
/// Resolution order: [resolve], then [mergeTheme] from ambient [ThemeData]
/// brightness. Per-screen overrides use a nested `Theme` with
/// `copyWith(extensions: […])`.
///
/// Layout, gestures, and freeze-on-exit live on `SelectableMessage` — this
/// extension only restyles the bundled checkbox / row tint. Replace the
/// chrome entirely with `ChatScrollView.selectionChromeBuilder`.
@immutable
class ChatSelectionThemeData extends ThemeExtension<ChatSelectionThemeData> {
  /// Creates selection-chrome tokens.
  const ChatSelectionThemeData({
    this.selectedTint,
    this.checkAccent,
    this.checkRing = const Color(0xFF8E8E93),
    this.checkmark = const Color(0xFFFFFFFF),
    this.slotWidth = 44,
    this.checkSize = 22,
    this.modeDuration = const Duration(milliseconds: 260),
    this.selectDuration = const Duration(milliseconds: 200),
  });

  /// Resolves from [context], falling back to [mergeTheme].
  factory ChatSelectionThemeData.resolve(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<ChatSelectionThemeData>() ??
        ChatSelectionThemeData.mergeTheme(theme);
  }

  /// Derives tokens from [theme] brightness when no extension is registered.
  factory ChatSelectionThemeData.mergeTheme(ThemeData theme) =>
      theme.brightness == Brightness.dark ? dark : light;

  /// Light-surface defaults (tint / check fill come from [ColorScheme.primary]).
  static const light = ChatSelectionThemeData();

  /// Dark-surface defaults.
  static const dark = ChatSelectionThemeData();

  /// Row overlay while selected. `null` → `primary` at 13% opacity.
  final Color? selectedTint;

  /// Checkbox fill. `null` → [ColorScheme.primary].
  final Color? checkAccent;

  /// Unselected checkbox ring.
  final Color checkRing;

  /// Checkmark stroke on the filled disc.
  final Color checkmark;

  /// Horizontal slide distance of the checkbox gutter.
  final double slotWidth;

  /// Checkbox diameter.
  final double checkSize;

  /// Duration of the mode (gutter slide) animation.
  final Duration modeDuration;

  /// Duration of the per-message selected animation.
  final Duration selectDuration;

  @override
  ChatSelectionThemeData copyWith({
    Color? selectedTint,
    Color? checkAccent,
    Color? checkRing,
    Color? checkmark,
    double? slotWidth,
    double? checkSize,
    Duration? modeDuration,
    Duration? selectDuration,
  }) => ChatSelectionThemeData(
    selectedTint: selectedTint ?? this.selectedTint,
    checkAccent: checkAccent ?? this.checkAccent,
    checkRing: checkRing ?? this.checkRing,
    checkmark: checkmark ?? this.checkmark,
    slotWidth: slotWidth ?? this.slotWidth,
    checkSize: checkSize ?? this.checkSize,
    modeDuration: modeDuration ?? this.modeDuration,
    selectDuration: selectDuration ?? this.selectDuration,
  );

  @override
  ChatSelectionThemeData lerp(
    covariant ChatSelectionThemeData? other,
    double t,
  ) {
    if (other == null) return this;
    return ChatSelectionThemeData(
      selectedTint: Color.lerp(selectedTint, other.selectedTint, t),
      checkAccent: Color.lerp(checkAccent, other.checkAccent, t),
      checkRing: Color.lerp(checkRing, other.checkRing, t)!,
      checkmark: Color.lerp(checkmark, other.checkmark, t)!,
      slotWidth: lerpDouble(slotWidth, other.slotWidth, t)!,
      checkSize: lerpDouble(checkSize, other.checkSize, t)!,
      modeDuration: lerpDuration(modeDuration, other.modeDuration, t),
      selectDuration: lerpDuration(selectDuration, other.selectDuration, t),
    );
  }
}
