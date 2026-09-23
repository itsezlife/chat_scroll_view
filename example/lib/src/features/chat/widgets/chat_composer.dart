import 'package:chat_chrome/chat_chrome.dart';
import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view_example/src/common/models/chat_message.dart';
import 'package:chat_scroll_view_example/src/common/widgets/measure_size.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Floating composer island for the widget chat demo.
///
/// Idle / edit: [ChatEnterView]. Selection mode: hidden — actions live on the
/// selection app bar, not a morph of this island.
/// Does not host [KeyboardPanel]; the screen places the panel in the keyboard
/// slot.
///
/// Chrome SoT is [composer] ([ChatComposerController]). The host owns lifetime
/// and drives reply / edit / emoji / IME without a [GlobalKey].
class ChatComposer extends StatefulWidget {
  /// Creates the composer.
  const ChatComposer({
    required this.composer,
    required this.selection,
    required this.dataSource,
    required this.onSend,
    required this.onEmojiPressed,
    this.onEditSelected,
    this.onSizeChanged,
    this.onAttachPressed,
    this.onMicPressed,
    this.bottomInset,
    this.onFieldTapWhilePanelOpen,
    this.glassKey,
    super.key,
  });

  /// Host-owned composer SoT.
  final ChatComposerController composer;

  /// When selection is active, the island is hidden.
  final ChatSelectionController selection;

  /// Source for edit content lookup ([beginEdit]).
  final ChatDataSource dataSource;

  /// Persists a trimmed message.
  final Future<void> Function(String text) onSend;

  /// Emoji / keyboard toggle (host toggles panel open flag).
  final VoidCallback onEmojiPressed;

  /// Saves edited content for one message.
  final Future<void> Function(int messageId, String text)? onEditSelected;

  /// Measured chrome height: island + island→keyboard gap (+ safe pad when
  /// the keyboard slot is closed).
  ///
  /// Does **not** include the keyboard / keyboard-panel slot — that is the
  /// separate `keyboard` term in [ChatViewportInsets.bottomPadding].
  final void Function(double height)? onSizeChanged;

  /// Attach button.
  final VoidCallback? onAttachPressed;

  /// Mic when empty.
  final VoidCallback? onMicPressed;

  /// Bottom inset.
  final ValueListenable<double>? bottomInset;

  /// Tap on the field while the keyboard panel is open (switch back to IME).
  final VoidCallback? onFieldTapWhilePanelOpen;

  /// Key on the glass island for bottom-fade cutout tracking.
  final GlobalKey? glassKey;

  @override
  State<ChatComposer> createState() => ChatComposerState();
}

/// State for [ChatComposer].
class ChatComposerState extends State<ChatComposer> {
  bool _selectionMode = false;

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
    super.dispose();
  }

  void _onSelectionChanged() {
    final mode = widget.selection.isSelectionMode;
    if (mode && widget.composer.mode.isEditing) {
      widget.composer.clear();
    }
    if (mode != _selectionMode) {
      if (mode) widget.composer.unfocus();
      setState(() => _selectionMode = mode);
    }
  }

  Future<void> _handleSend() async {
    final composer = widget.composer;
    if (composer.data.busy || !composer.data.enabled) return;
    final text = composer.text.text.trim();
    if (text.isEmpty) return;
    composer.setBusy(true);
    try {
      final mode = composer.mode;
      if (mode is ChatComposerMode$Editing) {
        final id = mode.id;
        if (id is! int) return;
        await widget.onEditSelected?.call(id, text);
        if (!mounted) return;
      } else {
        await widget.onSend(text);
        if (!mounted) return;
      }
      composer.clear();
    } finally {
      if (!composer.isDisposed) composer.setBusy(false);
    }
  }

  /// Loads [messageId] into the input for editing.
  void beginEdit(int messageId) {
    final content = widget.dataSource.getMessage(messageId)?.text;
    if (content == null) return;
    widget.selection.clear();
    widget.composer.text.value = TextEditingValue(
      text: content,
      selection: TextSelection.collapsed(offset: content.length),
    );
    widget.composer.beginEdit(id: messageId, preview: content);
  }

  void _cancelEdit() => widget.composer.clear();

  @override
  Widget build(BuildContext context) {
    if (_selectionMode) {
      return const SizedBox.shrink();
    }

    final composer = widget.composer;
    final safeBottom = MediaQuery.viewPaddingOf(context).bottom;
    const hPad = ChatInputMetrics.bubblePadding;

    return ValueListenableBuilder<ChatComposerMode>(
      valueListenable: composer.select((s) => s.data.mode),
      builder: (context, mode, _) {
        final isEditing = mode is ChatComposerMode$Editing;
        final child = MeasureSize(
          onChange: (size) =>
              widget.onSizeChanged?.call(size.height + safeBottom),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                hPad,
                10,
                hPad,
                ChatInputMetrics.bubbleBottomGap,
              ),
              child: ChatEnterView(
                composer: composer,
                onSend: _handleSend,
                onEmojiPressed: widget.onEmojiPressed,
                onAttachPressed: widget.onAttachPressed,
                onMicPressed: widget.onMicPressed,
                onFieldTapWhilePanelOpen: widget.onFieldTapWhilePanelOpen,
                glassKey: widget.glassKey,
                hintText: isEditing ? 'Edit message' : 'Message',
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
      },
    );
  }
}
