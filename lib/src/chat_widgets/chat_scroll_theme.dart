import 'package:chat_scroll_view/src/chat_widgets/chat_message_theme.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_scrollbar.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_selection_theme.dart';
import 'package:chat_scroll_view/src/chat_widgets/message_menu/chat_message_menu_theme.dart';
import 'package:flutter/material.dart';

/// Visual tokens for [ChatScrollView].
///
/// Colours and durations lerp under `AnimatedTheme`. Selection *chrome*
/// (layout / builder) is not a token — pass [ChatScrollView.selectionChromeBuilder]
/// per view.
///
/// Install app-wide with [ChatScrollTheme] or `ThemeData(extensions: […])`.
/// Sub-extensions ([ChatMessageThemeData], [ChatScrollbarThemeData],
/// [ChatSelectionThemeData]) still resolve when this object omits them.
@immutable
class ChatScrollThemeData extends ThemeExtension<ChatScrollThemeData> {
  /// Creates an (optionally partial) chat-scroll theme.
  ///
  /// Null fields fall through to the next source in [ChatScrollTheme.resolve].
  const ChatScrollThemeData({
    this.highlightColor,
    this.highlightDuration,
    this.message,
    this.scrollbar,
    this.selection,
    this.menu,
  });

  /// Default jump-to highlight fill (`#2196F3` at 25% opacity).
  static const Color defaultHighlightColor = Color(0x402196F3);

  /// Default jump-to highlight fade.
  static const Duration defaultHighlightDuration = Duration(milliseconds: 1500);

  /// Jump-target overlay colour. Null → [defaultHighlightColor].
  final Color? highlightColor;

  /// Jump-target overlay fade. Null → [defaultHighlightDuration].
  /// [Duration.zero] disables the overlay.
  final Duration? highlightDuration;

  /// Message-column layout. Null → [ChatMessageThemeData.resolve].
  final ChatMessageThemeData? message;

  /// Scrollbar colours. Null → [ChatScrollbarThemeData.resolve].
  final ChatScrollbarThemeData? scrollbar;

  /// Default selection-chrome tokens. Null → [ChatSelectionThemeData.resolve].
  final ChatSelectionThemeData? selection;

  /// Message-menu chrome tokens. Null → [ChatMessageMenuThemeData.resolve].
  final ChatMessageMenuThemeData? menu;

  @override
  ChatScrollThemeData copyWith({
    Color? highlightColor,
    Duration? highlightDuration,
    ChatMessageThemeData? message,
    ChatScrollbarThemeData? scrollbar,
    ChatSelectionThemeData? selection,
    ChatMessageMenuThemeData? menu,
  }) => ChatScrollThemeData(
    highlightColor: highlightColor ?? this.highlightColor,
    highlightDuration: highlightDuration ?? this.highlightDuration,
    message: message ?? this.message,
    scrollbar: scrollbar ?? this.scrollbar,
    selection: selection ?? this.selection,
    menu: menu ?? this.menu,
  );

  @override
  ChatScrollThemeData lerp(covariant ChatScrollThemeData? other, double t) {
    if (other == null) return this;
    return ChatScrollThemeData(
      highlightColor: Color.lerp(highlightColor, other.highlightColor, t),
      highlightDuration: t < 0.5 ? highlightDuration : other.highlightDuration,
      message: message == null
          ? other.message
          : other.message == null
          ? message
          : message!.lerp(other.message, t),
      scrollbar: scrollbar == null
          ? other.scrollbar
          : other.scrollbar == null
          ? scrollbar
          : scrollbar!.lerp(other.scrollbar, t),
      selection: selection == null
          ? other.selection
          : other.selection == null
          ? selection
          : selection!.lerp(other.selection, t),
      menu: menu == null
          ? other.menu
          : other.menu == null
          ? menu
          : menu!.lerp(other.menu, t),
    );
  }
}

/// Inherited [ChatScrollThemeData] for a subtree.
///
/// Prefer this when the app is not under `MaterialApp`, or when you want a
/// subtree to override `ThemeData.extensions` without rebuilding the whole
/// theme. Place it **below** `MaterialApp` so [ChatScrollTheme.resolve] can
/// still read [ColorScheme] for omitted sub-themes.
class ChatScrollTheme extends InheritedWidget {
  /// Provides [data] to descendant [ChatScrollView]s.
  const ChatScrollTheme({required this.data, required super.child, super.key});

  /// Theme data for the subtree.
  final ChatScrollThemeData data;

  /// Closest [ChatScrollThemeData], or `null` if none is in scope.
  static ChatScrollThemeData? maybeOf(
    BuildContext context, {
    bool listen = true,
  }) => listen
      ? context.dependOnInheritedWidgetOfExactType<ChatScrollTheme>()?.data
      : context.getInheritedWidgetOfExactType<ChatScrollTheme>()?.data;

  static Never _notFoundInheritedWidgetOfExactType() => throw ArgumentError(
    'Out of scope, not found inherited widget '
        'a ChatScrollTheme of the exact type',
    'out_of_scope',
  );

  /// The state from the closest instance of this class
  /// that encloses the given context.
  /// e.g. `Theme.of(context)`
  static ChatScrollThemeData of(BuildContext context, {bool listen = true}) =>
      maybeOf(context, listen: listen) ?? _notFoundInheritedWidgetOfExactType();

  /// Message-column tokens for [context].
  ///
  /// One inherited lookup — does not resolve scrollbar / selection. Prefer
  /// this from message widgets over [resolve].
  static ChatMessageThemeData messageOf(BuildContext context) =>
      maybeOf(context)?.message ?? ChatMessageThemeData.resolve(context);

  /// Message-menu tokens for [context].
  static ChatMessageMenuThemeData menuOf(BuildContext context) {
    final nested =
        maybeOf(context)?.menu ??
        Theme.of(context).extension<ChatScrollThemeData>()?.menu;
    return ChatMessageMenuThemeData.resolve(context).merge(nested);
  }

  /// Fully resolved tokens for [context].
  ///
  /// Order: [ChatScrollTheme] → `ThemeData.extension<ChatScrollThemeData>()`
  /// → per-field fallbacks ([ChatMessageThemeData.resolve],
  /// [ChatScrollbarThemeData.resolve], [ChatSelectionThemeData.resolve],
  /// package defaults).
  static ChatScrollThemeData resolve(BuildContext context) {
    final inherited = maybeOf(context);
    final ext = Theme.of(context).extension<ChatScrollThemeData>();
    final base = inherited ?? ext ?? const ChatScrollThemeData();
    return ChatScrollThemeData(
      highlightColor:
          base.highlightColor ?? ChatScrollThemeData.defaultHighlightColor,
      highlightDuration:
          base.highlightDuration ??
          ChatScrollThemeData.defaultHighlightDuration,
      message: base.message ?? ChatMessageThemeData.resolve(context),
      scrollbar: base.scrollbar ?? ChatScrollbarThemeData.resolve(context),
      selection: base.selection ?? ChatSelectionThemeData.resolve(context),
      menu: base.menu ?? ChatMessageMenuThemeData.resolve(context),
    );
  }

  @override
  bool updateShouldNotify(covariant ChatScrollTheme oldWidget) =>
      !identical(data, oldWidget.data);
}
