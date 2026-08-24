import 'package:chat_chrome/chat_chrome.dart';
import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view_example/src/common/models/chat_message.dart';
import 'package:chat_scroll_view_example/src/common/widgets/measure_size.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Floating Telegram-shaped composer island for the widget chat demo.
///
/// Idle / edit: [ChatEnterView]. Selection mode: hidden — actions live on the
/// selection app bar (Telegram action mode), not a morph of this island.
/// Does not host [EmojiPanel]; the screen places the panel in the keyboard slot.
class ChatComposer extends StatefulWidget {
  /// Creates the composer.
  const ChatComposer({
    required this.selection,
    required this.dataSource,
    required this.onSend,
    required this.onEmojiPressed,
    required this.emojiIconState,
    this.onEditSelected,
    this.onSizeChanged,
    this.onAttachPressed,
    this.onMicPressed,
    this.bottomInset,
    this.onFieldTapWhileEmojiOpen,
    this.glassKey,
    super.key,
  });

  /// When selection is active, the island is hidden.
  final ChatSelectionController selection;

  /// Source for edit content lookup.
  final ChatDataSource dataSource;

  /// Persists a trimmed message.
  final Future<void> Function(String text) onSend;

  /// Emoji / keyboard toggle (host toggles panel open flag).
  final VoidCallback onEmojiPressed;

  /// Left emoji-button face.
  final ChatEnterEmojiIconState emojiIconState;

  /// Saves edited content for one message.
  final Future<void> Function(int messageId, String text)? onEditSelected;

  /// Measured chrome height: island + island→keyboard gap (+ safe pad when
  /// the keyboard slot is closed).
  ///
  /// Does **not** include the keyboard / emoji-panel slot — that is the
  /// separate `keyboard` term in [ChatViewportInsets.bottomPadding].
  final void Function(double height)? onSizeChanged;

  /// Attach button.
  final VoidCallback? onAttachPressed;

  /// Mic when empty.
  final VoidCallback? onMicPressed;

  /// Bottom inset.
  final ValueListenable<double>? bottomInset;

  /// Tap on the field while emoji panel is open (switch back to IME).
  final VoidCallback? onFieldTapWhileEmojiOpen;

  /// Key on the glass island for bottom-fade cutout tracking.
  final GlobalKey? glassKey;

  @override
  State<ChatComposer> createState() => ChatComposerState();
}

/// State for [ChatComposer].
class ChatComposerState extends State<ChatComposer> {
  final TextEditingController _text = TextEditingController();
  final FocusNode _focus = FocusNode(debugLabel: 'ChatComposer');
  final GlobalKey<ChatEnterViewState> _enterKey =
      GlobalKey<ChatEnterViewState>();

  bool _selectionMode = false;
  bool _sending = false;
  int? _editingMessageId;

  /// Exposed for emoji insertion from the panel.
  TextEditingController get textController => _text;

  @override
  void initState() {
    super.initState();
    _selectionMode = widget.selection.isSelectionMode;
    widget.selection.addListener(_onSelectionChanged);
  }

  @override
  void didUpdateWidget(ChatComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.selection, widget.selection)) {
      oldWidget.selection.removeListener(_onSelectionChanged);
      widget.selection.addListener(_onSelectionChanged);
      _onSelectionChanged();
    }
  }

  @override
  void dispose() {
    widget.selection.removeListener(_onSelectionChanged);
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onSelectionChanged() {
    final mode = widget.selection.isSelectionMode;
    if (mode && _editingMessageId != null) {
      _text.clear();
      _editingMessageId = null;
    }
    if (mode != _selectionMode) {
      if (mode) _focus.unfocus();
      setState(() => _selectionMode = mode);
    }
  }

  /// Inserts [text] at the caret.
  void insertText(String text) {
    final value = _text.value;
    final start = value.selection.start >= 0
        ? value.selection.start
        : value.text.length;
    final end = value.selection.end >= 0
        ? value.selection.end
        : value.text.length;
    final next = value.text.replaceRange(start, end, text);
    _text.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + text.length),
    );
  }

  /// Deletes the last grapheme cluster.
  void backspace() => emojiBackspace(_text);

  /// Opens soft keyboard.
  void requestKeyboard() {
    _enterKey.currentState?.requestKeyboard();
  }

  /// Arms IME-suppress bypass before a composer field tap steals focus.
  void prepareKeyboardHandoff() {
    _enterKey.currentState?.prepareKeyboardHandoff();
  }

  /// Hides soft keyboard.
  void hideKeyboard() => _enterKey.currentState?.hideKeyboard();

  /// Hides soft IME; keeps caret + hardware keyboard (Telegram emoji open).
  void hideKeyboardRetainingFocus() =>
      _enterKey.currentState?.hideKeyboardRetainingFocus();

  /// Drops focus — use only when the field should fully resign input.
  void unfocus() => _focus.unfocus();

  Future<void> _handleSend() async {
    if (_sending) return;
    final text = _text.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      final editingId = _editingMessageId;
      if (editingId != null) {
        await widget.onEditSelected?.call(editingId, text);
        if (!mounted) return;
        _editingMessageId = null;
      } else {
        await widget.onSend(text);
        if (!mounted) return;
      }
      _text.clear();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  static String? _contentOf(IChatMessage? message) => switch (message) {
    UserChatMessage(:final content) => content,
    SystemChatMessage(:final content) => content,
    _ => null,
  };

  /// Loads [messageId] into the input for editing.
  void beginEdit(int messageId) {
    final content = _contentOf(widget.dataSource.getMessage(messageId));
    if (content == null) return;
    widget.selection.clear();
    setState(() {
      _editingMessageId = messageId;
      _text.value = TextEditingValue(
        text: content,
        selection: TextSelection.collapsed(offset: content.length),
      );
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      requestKeyboard();
    });
  }

  void _cancelEdit() {
    _text.clear();
    if (_editingMessageId == null) return;
    setState(() => _editingMessageId = null);
  }

  @override
  Widget build(BuildContext context) {
    if (_selectionMode) {
      return const SizedBox.shrink();
    }

    final isEditing = _editingMessageId != null;
    final safeBottom = MediaQuery.viewPaddingOf(context).bottom;
    const hPad = ChatInputMetrics.bubblePadding;

    final child = MeasureSize(
      onChange: (size) => widget.onSizeChanged?.call(size.height + safeBottom),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            hPad,
            10,
            hPad,
            ChatInputMetrics.bubbleBottomGap,
          ),
          child: ChatEnterView(
            key: _enterKey,
            controller: _text,
            focusNode: _focus,
            onSend: _handleSend,
            onEmojiPressed: widget.onEmojiPressed,
            onAttachPressed: widget.onAttachPressed,
            onMicPressed: widget.onMicPressed,
            emojiIconState: widget.emojiIconState,
            onFieldTapWhileEmojiOpen: widget.onFieldTapWhileEmojiOpen,
            glassKey: widget.glassKey,
            hintText: isEditing ? 'Edit message' : 'Message',
            isEditing: isEditing,
            sending: _sending,
            onCancelEdit: isEditing ? _cancelEdit : null,
            topBanner: isEditing
                ? const ChatEnterTopBanner(
                    title: 'Edit message',
                    subtitle: 'Tap ✕ to cancel',
                    isEdit: true,
                  )
                : null,
            onTopBannerClose: isEditing ? _cancelEdit : null,
          ),
        ),
      ),
    );

    final bottomInset = widget.bottomInset;
    if (bottomInset == null) return child;

    return ValueListenableBuilder(
      valueListenable: bottomInset,
      child: child,
      builder: (context, bottomInset, child) => Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: child,
      ),
    );
  }
}
