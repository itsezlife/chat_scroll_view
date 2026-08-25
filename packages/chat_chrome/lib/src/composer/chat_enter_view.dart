import 'package:chat_chrome/src/composer/chat_enter_icons.dart';
import 'package:chat_chrome/src/composer/chat_enter_top_view.dart';
import 'package:chat_chrome/src/composer/chat_input_metrics.dart';
import 'package:chat_chrome/src/glass/telegram_glass.dart';
import 'package:chat_chrome/src/glass/telegram_glass_style.dart';
import 'package:chat_chrome/src/theme/chat_chrome_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Optional reply / edit banner model for [ChatEnterView].
@immutable
class ChatEnterTopBanner {
  /// Creates a reply or edit banner.
  const ChatEnterTopBanner({
    required this.title,
    required this.subtitle,
    this.isEdit = false,
  });

  /// Author name or "Edit message".
  final String title;

  /// Preview text.
  final String subtitle;

  /// Edit vs reply chrome.
  final bool isEdit;
}

/// Floating input island (glass bubble).
///
/// Transparent outer host — the painted shape is the 22dp-radius island with
/// 7dp horizontal margins (see [ChatInputMetrics]). Selection actions do not
/// live here; Those live on the action / selection chrome.
class ChatEnterView extends StatefulWidget {
  /// Creates the enter view.
  const ChatEnterView({
    required this.controller,
    required this.focusNode,
    required this.onSend,
    required this.onEmojiPressed,
    this.onAttachPressed,
    this.onMicPressed,
    this.hintText = 'Message',
    this.emojiIconState = ChatEnterEmojiIconState.smile,
    this.topBanner,
    this.onTopBannerClose,
    this.enabled = true,
    this.sending = false,
    this.isEditing = false,
    this.onCancelEdit,
    this.maxWidth = 620,
    this.onFieldTapWhilePanelOpen,
    this.glassKey,
    super.key,
  });

  /// Text field controller.
  final TextEditingController controller;

  /// Field focus.
  final FocusNode focusNode;

  /// Send / confirm.
  final VoidCallback? onSend;

  /// Emoji / keyboard toggle.
  final VoidCallback onEmojiPressed;

  /// Attach button (optional).
  final VoidCallback? onAttachPressed;

  /// Mic when field empty (optional).
  final VoidCallback? onMicPressed;

  /// Field hint.
  final String hintText;

  /// Left emoji-button face.
  final ChatEnterEmojiIconState emojiIconState;

  /// Reply / edit strip.
  final ChatEnterTopBanner? topBanner;

  /// Clears [topBanner].
  final VoidCallback? onTopBannerClose;

  /// Disables editing.
  final bool enabled;

  /// In-flight send.
  final bool sending;

  /// Edit mode (check icon).
  final bool isEditing;

  /// Cancel edit affordance.
  final VoidCallback? onCancelEdit;

  /// Max content width.
  final double maxWidth;

  /// Key on the liquid-glass island (for fade cutout tracking).
  final GlobalKey? glassKey;

  /// Fired when the user taps the field while the keyboard panel is open
  /// (tap input → close panel, show IME).
  final VoidCallback? onFieldTapWhilePanelOpen;

  /// Default composer height (`DEFAULT_HEIGHT` / island paint height).
  static const double rowHeight = ChatInputMetrics.islandHeight;

  @override
  State<ChatEnterView> createState() => ChatEnterViewState();
}

/// State for [ChatEnterView].
class ChatEnterViewState extends State<ChatEnterView> {
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _hasText = widget.controller.text.trim().isNotEmpty;
    widget.controller.addListener(_onText);
    widget.focusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(ChatEnterView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_onText);
      widget.controller.addListener(_onText);
      _hasText = widget.controller.text.trim().isNotEmpty;
    }
    if (oldWidget.emojiIconState != widget.emojiIconState &&
        _suppressSoftKeyboard) {
      _suppressIme();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onText);
    widget.focusNode.removeListener(_onFocusChange);
    super.dispose();
  }

  var _allowImeOnce = false;

  /// Keyboard panel open → keyboard icon; suppress OS IME while focused.
  bool get _suppressSoftKeyboard =>
      widget.emojiIconState == ChatEnterEmojiIconState.keyboard;

  void _suppressIme() {
    SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
  }

  void _onFocusChange() {
    if (_allowImeOnce) {
      _allowImeOnce = false;
      // Search→composer tap transfers focus before [onTap]; keep soft IME up.
      SystemChannels.textInput.invokeMethod<void>('TextInput.show');
      return;
    }
    if (!_suppressSoftKeyboard || !widget.focusNode.hasFocus) return;
    _suppressIme();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _suppressSoftKeyboard) _suppressIme();
    });
  }

  void _onText() {
    final next = widget.controller.text.trim().isNotEmpty;
    if (next != _hasText) setState(() => _hasText = next);
  }

  /// Arms one focus gain so IME-suppress does not hide the soft keyboard.
  ///
  /// Call on pointer-down of the composer field while the keyboard panel is
  /// open — [TextField] steals focus before [onTap], ahead of [requestKeyboard].
  void prepareKeyboardHandoff() {
    _allowImeOnce = true;
  }

  /// Programmatic focus + IME show.
  ///
  /// Bypasses keyboard-panel IME suppression once so focus handoff from the
  /// emoji search field does not hide-then-show the soft keyboard.
  void requestKeyboard() {
    final alreadyFocused = widget.focusNode.hasFocus;
    // If focus already landed via a prepared tap, do not leave the arm stuck.
    _allowImeOnce = !alreadyFocused;
    widget.focusNode.requestFocus();
    SystemChannels.textInput.invokeMethod<void>('TextInput.show');
  }

  /// Hides IME.
  void hideKeyboard() {
    SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
  }

  /// Hides soft IME but keeps the field focused (keyboard panel open).
  ///
  /// Call only while [ChatEnterEmojiIconState.keyboard] suppresses IME show.
  void hideKeyboardRetainingFocus() {
    _suppressIme();
    if (!widget.focusNode.hasFocus) {
      widget.focusNode.requestFocus();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _suppressIme();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = ChatChromeTheme.of(context);
    final brightness = Theme.of(context).brightness;
    final glassStyle = TelegramGlassStyle.composerIsland(
      panelBackground: colors.messagePanelBackground,
      brightness: brightness,
      cornerRadius: ChatInputMetrics.bubbleRadius,
    );
    return Material(
      color: Colors.transparent,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: widget.maxWidth),
          child: TelegramGlass(
            key: widget.glassKey,
            style: glassStyle,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (widget.topBanner != null)
                  ChatEnterTopView(
                    title: widget.topBanner!.title,
                    subtitle: widget.topBanner!.subtitle,
                    isEdit: widget.topBanner!.isEdit,
                    onClose: widget.onTopBannerClose ?? () {},
                  ),
                _InputRow(
                  controller: widget.controller,
                  focusNode: widget.focusNode,
                  colors: colors,
                  hintText: widget.hintText,
                  emojiIconState: widget.emojiIconState,
                  onEmojiPressed: widget.onEmojiPressed,
                  onAttachPressed: widget.onAttachPressed,
                  onSend: widget.onSend,
                  onMicPressed: widget.onMicPressed,
                  hasText: _hasText,
                  sending: widget.sending,
                  isEditing: widget.isEditing,
                  onCancelEdit: widget.onCancelEdit,
                  enabled: widget.enabled,
                  onFieldTapWhilePanelOpen: widget.onFieldTapWhilePanelOpen,
                  onPrepareKeyboardHandoff:
                      widget.onFieldTapWhilePanelOpen == null
                      ? null
                      : prepareKeyboardHandoff,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InputRow extends StatelessWidget {
  const _InputRow({
    required this.controller,
    required this.focusNode,
    required this.colors,
    required this.hintText,
    required this.emojiIconState,
    required this.onEmojiPressed,
    required this.onAttachPressed,
    required this.onSend,
    required this.onMicPressed,
    required this.hasText,
    required this.sending,
    required this.isEditing,
    required this.onCancelEdit,
    required this.enabled,
    this.onFieldTapWhilePanelOpen,
    this.onPrepareKeyboardHandoff,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ChatChromeColors colors;
  final String hintText;
  final ChatEnterEmojiIconState emojiIconState;
  final VoidCallback onEmojiPressed;
  final VoidCallback? onAttachPressed;
  final VoidCallback? onSend;
  final VoidCallback? onMicPressed;
  final bool hasText;
  final bool sending;
  final bool isEditing;
  final VoidCallback? onCancelEdit;
  final bool enabled;
  final VoidCallback? onFieldTapWhilePanelOpen;
  final VoidCallback? onPrepareKeyboardHandoff;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Horizontal only — vertical chrome is the 44 island (`DEFAULT_HEIGHT`).
      // Extra top/bottom pad made the glass taller than 44, so radius 22 no
      // longer read as a stadium (half-height pill).
      padding: const EdgeInsetsDirectional.only(start: 2, end: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          ChatEnterIconButton(
            icon: emojiIconFor(emojiIconState),
            morph: true,
            onPressed: enabled ? onEmojiPressed : null,
          ),
          Expanded(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: ChatEnterView.rowHeight,
              ),
              child: Padding(
                padding: const EdgeInsetsDirectional.only(
                  top: 9,
                  bottom: 10,
                  end: 4,
                ),
                child: Listener(
                  behavior: HitTestBehavior.translucent,
                  onPointerDown: onPrepareKeyboardHandoff == null
                      ? null
                      : (_) => onPrepareKeyboardHandoff!(),
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    enabled: enabled,
                    minLines: 1,
                    maxLines: 6,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    onTap: onFieldTapWhilePanelOpen,
                    cursorColor: colors.messagePanelCursor,
                    style: TextStyle(
                      color: colors.messagePanelText,
                      fontSize: 18,
                      height: 1.25,
                    ),
                    decoration: InputDecoration.collapsed(
                      hintText: hintText,
                      hintStyle: TextStyle(
                        color: colors.messagePanelHint,
                        fontSize: 18,
                        height: 1.25,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          ChatEnterIconButton(
            icon: Icons.attach_file_rounded,
            onPressed: enabled ? onAttachPressed : null,
          ),
          ChatEnterSendMicButton(
            hasText: hasText,
            onSend: onSend,
            onMic: onMicPressed,
            sending: sending,
            isEditing: isEditing,
          ),
        ],
      ),
    );
  }
}
