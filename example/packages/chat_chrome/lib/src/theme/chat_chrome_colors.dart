import 'package:flutter/material.dart';

/// Theme colors for composer + emoji panel.
@immutable
class ChatChromeColors {
  /// Light defaults.
  const ChatChromeColors({
    this.panelBackground = const Color(0xFFF0F2F5),
    this.panelIcon = const Color(0xFF9DA4AB),
    this.panelIconSelected = const Color(0xFF5E6976),
    this.panelBackspace = const Color(0xFF8C9197),
    this.panelShadowLine = const Color(0x12000000),
    this.panelTabSelector = const Color(0xFFE2E5E7),
    this.panelTabSelectorLine = const Color(0xFF56ABF0),
    this.panelStickerSetName = const Color(0xFF8B9197),
    this.panelEmptyText = const Color(0xFF949BA1),
    this.panelFloatingFill = const Color(0xFFE8EAED),
    this.panelFloatingSelected = const Color(0xFFFFFFFF),
    this.panelFloatingText = const Color(0xFF000000),
    this.panelFloatingTextMuted = const Color(0x99000000),
    this.emojiSearchFill = const Color(0x0F000000),
    this.emojiSearchIcon = const Color(0x66000000),
    this.emojiSearchHint = const Color(0x73000000),
    this.emojiSearchText = const Color(0xCC000000),
    this.messagePanelBackground = const Color(0xFFFFFFFF),
    this.messagePanelText = const Color(0xFF000000),
    this.messagePanelHint = const Color(0xFF858A84),
    this.messagePanelCursor = const Color(0xFF54A1DB),
    this.messagePanelIcons = const Color(0xFF8E959B),
    this.messagePanelSend = const Color(0xFF54A1DB),
    this.messagePanelShadow = const Color(0xFF000000),
    this.contentBottomFade = const Color(0xFFFFFFFF),
    this.replyLine = const Color(0xFF54A1DB),
    this.replyName = const Color(0xFF54A1DB),
    this.replyText = const Color(0xFF8A8A8A),
  });

  /// Dark defaults.
  const ChatChromeColors.dark({
    this.panelBackground = const Color(0xFF20242A),
    this.panelIcon = const Color(0x80FFFFFF),
    this.panelIconSelected = const Color(0xFFFFFFFF),
    this.panelBackspace = const Color(0x7DFFFFFF),
    this.panelShadowLine = const Color(0x1E000000),
    this.panelTabSelector = const Color(0x0ACDEAFF),
    this.panelTabSelectorLine = const Color(0xFF64B5EF),
    this.panelStickerSetName = const Color(0x73FFFFFF),
    this.panelEmptyText = const Color(0xFF7D7D7E),
    this.panelFloatingFill = const Color(0xFF2C2C2E),
    this.panelFloatingSelected = const Color(0xFF3A3A3C),
    this.panelFloatingText = const Color(0xFFFFFFFF),
    this.panelFloatingTextMuted = const Color(0x99FFFFFF),
    this.emojiSearchFill = const Color(0x0FFFFFFF),
    this.emojiSearchIcon = const Color(0x66FFFFFF),
    this.emojiSearchHint = const Color(0x73FFFFFF),
    this.emojiSearchText = const Color(0xCCFFFFFF),
    this.messagePanelBackground = const Color(0xFF20242A),
    this.messagePanelText = const Color(0xFFFFFFFF),
    this.messagePanelHint = const Color(0x99FFFFFF),
    this.messagePanelCursor = const Color(0xFFFFFFFF),
    this.messagePanelIcons = const Color(0xE6FFFFFF),
    this.messagePanelSend = const Color(0xFF54A1DB),
    this.messagePanelShadow = const Color(0xFF000000),
    // Soft wallpaper-scrim stand-in: darker than [panelBackground] for edge
    // contrast, but not pure black (reads as a heavy nav brick).
    this.contentBottomFade = const Color(0xFF15191E),
    this.replyLine = const Color(0xFF54A1DB),
    this.replyName = const Color(0xFF54A1DB),
    this.replyText = const Color(0x99FFFFFF),
  });

  /// Picks light/dark from [brightness].
  factory ChatChromeColors.forBrightness(Brightness brightness) =>
      brightness == Brightness.dark
          ? const ChatChromeColors.dark()
          : const ChatChromeColors();

  /// `key_chat_emojiPanelBackground`.
  final Color panelBackground;

  /// `key_chat_emojiPanelIcon`.
  final Color panelIcon;

  /// `key_chat_emojiPanelIconSelected`.
  final Color panelIconSelected;

  /// `key_chat_emojiPanelBackspace`.
  final Color panelBackspace;

  /// `key_chat_emojiPanelShadowLine`.
  final Color panelShadowLine;

  /// `key_chat_emojiPanelStickerPackSelector`.
  final Color panelTabSelector;

  /// `key_chat_emojiPanelStickerPackSelectorLine`.
  final Color panelTabSelectorLine;

  /// `key_chat_emojiPanelStickerSetName`.
  final Color panelStickerSetName;

  /// `key_chat_emojiPanelEmptyText` (empty search / no-emoji placeholder).
  final Color panelEmptyText;

  /// Floating type-pill / backspace fill (solid, opaque).
  final Color panelFloatingFill;

  /// Selected segment capsule inside the type pill (solid).
  final Color panelFloatingSelected;

  /// Active text / backspace icon on floating chrome.
  final Color panelFloatingText;

  /// Idle type-tab label on floating chrome.
  final Color panelFloatingTextMuted;

  /// Glass search pill fill (`getGlassIconColor(0.06)`).
  final Color emojiSearchFill;

  /// Glass search / clear icon (`getGlassIconColor(0.4)`).
  final Color emojiSearchIcon;

  /// Glass search hint (`getGlassIconColor(0.45)`).
  final Color emojiSearchHint;

  /// Glass search input text (`getGlassIconColor(0.8)`).
  final Color emojiSearchText;

  /// `key_chat_messagePanelBackground`.
  final Color messagePanelBackground;

  /// `key_chat_messagePanelText`.
  final Color messagePanelText;

  /// `key_chat_messagePanelHint`.
  final Color messagePanelHint;

  /// `key_chat_messagePanelCursor`.
  final Color messagePanelCursor;

  /// `key_chat_messagePanelIcons`.
  final Color messagePanelIcons;

  /// `key_chat_messagePanelSend`.
  final Color messagePanelSend;

  /// `key_chat_messagePanelShadow`.
  final Color messagePanelShadow;

  /// Bottom content fade under composer / keyboard.
  ///
  /// Wallpaper-blur stand-in. MUST differ from [panelBackground] so the emoji
  /// sheet top radius and island→panel gap stay readable.
  final Color contentBottomFade;

  /// Reply accent line.
  final Color replyLine;

  /// Reply author name.
  final Color replyName;

  /// Reply preview body.
  final Color replyText;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatChromeColors &&
          panelBackground == other.panelBackground &&
          panelIcon == other.panelIcon &&
          panelIconSelected == other.panelIconSelected &&
          panelBackspace == other.panelBackspace &&
          panelShadowLine == other.panelShadowLine &&
          panelTabSelector == other.panelTabSelector &&
          panelTabSelectorLine == other.panelTabSelectorLine &&
          panelStickerSetName == other.panelStickerSetName &&
          panelEmptyText == other.panelEmptyText &&
          panelFloatingFill == other.panelFloatingFill &&
          panelFloatingSelected == other.panelFloatingSelected &&
          panelFloatingText == other.panelFloatingText &&
          panelFloatingTextMuted == other.panelFloatingTextMuted &&
          emojiSearchFill == other.emojiSearchFill &&
          emojiSearchIcon == other.emojiSearchIcon &&
          emojiSearchHint == other.emojiSearchHint &&
          emojiSearchText == other.emojiSearchText &&
          messagePanelBackground == other.messagePanelBackground &&
          messagePanelText == other.messagePanelText &&
          messagePanelHint == other.messagePanelHint &&
          messagePanelCursor == other.messagePanelCursor &&
          messagePanelIcons == other.messagePanelIcons &&
          messagePanelSend == other.messagePanelSend &&
          messagePanelShadow == other.messagePanelShadow &&
          contentBottomFade == other.contentBottomFade &&
          replyLine == other.replyLine &&
          replyName == other.replyName &&
          replyText == other.replyText;

  @override
  int get hashCode => Object.hashAll(<Object?>[
        panelBackground,
        panelIcon,
        panelIconSelected,
        panelBackspace,
        panelShadowLine,
        panelTabSelector,
        panelTabSelectorLine,
        panelStickerSetName,
        panelEmptyText,
        panelFloatingFill,
        panelFloatingSelected,
        panelFloatingText,
        panelFloatingTextMuted,
        emojiSearchFill,
        emojiSearchIcon,
        emojiSearchHint,
        emojiSearchText,
        messagePanelBackground,
        messagePanelText,
        messagePanelHint,
        messagePanelCursor,
        messagePanelIcons,
        messagePanelSend,
        messagePanelShadow,
        contentBottomFade,
        replyLine,
        replyName,
        replyText,
      ]);
}

/// Inherited theme for chat_chrome widgets.
class ChatChromeTheme extends InheritedWidget {
  /// Provides [colors] to descendants.
  const ChatChromeTheme({
    required this.colors,
    required super.child,
    super.key,
  });

  /// Active tokens.
  final ChatChromeColors colors;

  /// Resolves theme; falls back to light defaults.
  static ChatChromeColors of(BuildContext context) {
    final scoped =
        context.dependOnInheritedWidgetOfExactType<ChatChromeTheme>();
    return scoped?.colors ?? const ChatChromeColors();
  }

  @override
  bool updateShouldNotify(ChatChromeTheme oldWidget) =>
      oldWidget.colors != colors;
}
