import 'package:chat_chrome/src/motion/keyboard_panel_motion.dart';
import 'package:chat_chrome/src/panel/emoji_search_state_icon.dart';
import 'package:chat_chrome/src/theme/chat_chrome_colors.dart';
import 'package:flutter/material.dart';

/// Sticky keyboard-panel search chrome (50dp host, 36dp glass pill).
///
/// Idle: host translates with the grid search spacer. Focus / tap opens search
/// mode via [onOpenSearch]. Bottom shadow shows only while search is open and
/// content has scrolled under the field.
///
/// Leading icon morphs via [EmojiSearchStateIcon] (magnifier → progress → back).
class EmojiSearchField extends StatefulWidget {
  /// Creates the search field.
  const EmojiSearchField({
    required this.controller,
    required this.focusNode,
    required this.searchOpen,
    required this.showShadow,
    required this.onOpenSearch,
    this.searchBusy = false,
    this.searchSettled = false,
    this.hintText = 'Search',
    super.key,
  });

  /// Query controller.
  final TextEditingController controller;

  /// Focus node owned by the panel shell.
  final FocusNode focusNode;

  /// Whether search mode is open (field pinned, strip hidden).
  final bool searchOpen;

  /// Whether the bottom shadow line under the field is visible.
  final bool showShadow;

  /// Keyword search in flight — leading icon shows progress.
  final bool searchBusy;

  /// Whether a keyword search has completed for a non-empty query.
  ///
  /// Drives leading back (after progress). False while debouncing the first
  /// character so the icon stays magnifier until loading starts.
  final bool searchSettled;

  /// Fired when the user taps the field while search is closed.
  final VoidCallback onOpenSearch;

  /// Hint.
  final String hintText;

  /// Search field layout height (`searchFieldHeight`).
  static const double height = 50;

  /// Painted pill height.
  static const double pillHeight = 36;

  /// Pill corner radius (full capsule on [pillHeight]).
  static const double pillRadius = 18;

  /// Left / right pill margins.
  static const double pillMarginH = 10;

  /// Top margin (emoji type).
  static const double pillMarginTop = 6;

  /// Bottom margin (emoji type).
  static const double pillMarginBottom = 8;

  /// Search / clear hit boxes.
  static const double iconSize = 36;

  @override
  State<EmojiSearchField> createState() => _EmojiSearchFieldState();
}

class _EmojiSearchFieldState extends State<EmojiSearchField>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shadow;
  var _hasText = false;

  @override
  void initState() {
    super.initState();
    _hasText = widget.controller.text.isNotEmpty;
    widget.controller.addListener(_onText);
    _shadow = AnimationController(
      vsync: this,
      duration: KeyboardPanelMotion.shadowDuration,
      value: widget.showShadow ? 1 : 0,
    );
  }

  @override
  void didUpdateWidget(EmojiSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_onText);
      widget.controller.addListener(_onText);
      _hasText = widget.controller.text.isNotEmpty;
    }
    if (oldWidget.showShadow != widget.showShadow) {
      if (widget.showShadow) {
        _shadow.forward();
      } else {
        _shadow.reverse();
      }
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onText);
    _shadow.dispose();
    super.dispose();
  }

  void _onText() {
    final next = widget.controller.text.isNotEmpty;
    if (next == _hasText) return;
    setState(() => _hasText = next);
  }

  void _onFieldTap() {
    if (!widget.searchOpen) {
      widget.onOpenSearch();
    }
  }

  void _clear() {
    widget.controller.clear();
  }

  /// Leading: magnifier → progress → back (`SearchStateDrawable`).
  ///
  /// Back only after a settled keyword search — not on the first keystroke
  /// before the progress delay fires.
  EmojiSearchIconState get _leadingState {
    if (widget.searchBusy) return EmojiSearchIconState.progress;
    if (_hasText && widget.searchSettled) return EmojiSearchIconState.back;
    return EmojiSearchIconState.search;
  }

  @override
  Widget build(BuildContext context) {
    final colors = ChatChromeTheme.of(context);
    final leading = _leadingState;
    return SizedBox(
      height: EmojiSearchField.height,
      width: double.infinity,
      child: Stack(
        children: <Widget>[
          Positioned(
            left: EmojiSearchField.pillMarginH,
            right: EmojiSearchField.pillMarginH,
            top: EmojiSearchField.pillMarginTop,
            height: EmojiSearchField.pillHeight,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.emojiSearchFill,
                borderRadius: BorderRadius.circular(
                  EmojiSearchField.pillRadius,
                ),
              ),
              child: Row(
                children: <Widget>[
                  SizedBox(
                    width: EmojiSearchField.iconSize,
                    height: EmojiSearchField.iconSize,
                    child: Material(
                      type: MaterialType.transparency,
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: leading == EmojiSearchIconState.back
                            ? _clear
                            : null,
                        child: Center(
                          child: EmojiSearchStateIcon(
                            state: leading,
                            color: colors.emojiSearchIcon,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      controller: widget.controller,
                      focusNode: widget.focusNode,
                      style: TextStyle(
                        color: colors.emojiSearchText,
                        fontSize: 16,
                      ),
                      cursorColor: colors.messagePanelCursor,
                      onTap: _onFieldTap,
                      decoration: InputDecoration.collapsed(
                        hintText: widget.hintText,
                        hintStyle: TextStyle(
                          color: colors.emojiSearchHint,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                  // Trailing clear stays visible during progress (Telegram).
                  if (_hasText)
                    SizedBox(
                      width: EmojiSearchField.iconSize,
                      height: EmojiSearchField.iconSize,
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        onPressed: _clear,
                        icon: Icon(
                          Icons.close_rounded,
                          size: 20,
                          color: colors.emojiSearchIcon,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: AnimatedBuilder(
              animation: _shadow,
              builder: (context, _) {
                final t = Curves.easeOut.transform(_shadow.value);
                if (t <= 0.001) return const SizedBox.shrink();
                // Paint alpha — not [FadeTransition] (saveLayer on open/scroll).
                return ColoredBox(
                  color: colors.panelShadowLine.withValues(
                    alpha: colors.panelShadowLine.a * t,
                  ),
                  child: const SizedBox(height: 1),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
