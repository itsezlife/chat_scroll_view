// ignore_for_file: prefer_expression_function_bodies

import 'package:chat_scroll_view_example/src/features/chat/widgets/side_controls/chat_side_control_fab.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/side_controls/chat_side_controls_stack.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Drop-in side-controls overlay: search up/down + page-down in one stack.
///
/// While [searching] is true, search chevrons animate in and page-down
/// animates out (Telegram search mode). Slots share one layout so they
/// move together.
class ChatSideControlsBar extends StatelessWidget {
  /// Creates the demo side-controls bar.
  const ChatSideControlsBar({
    required this.pageDown,
    required this.pageDownVisible,
    required this.searching,
    this.bottomInset,
    this.onSearchUp,
    this.onSearchDown,
    this.searchHitCount = 0,
    this.searchUpEnabled = true,
    this.searchDownEnabled = true,
    super.key,
  });

  /// Page-down control built with [ChatScrollToBottomButton.embedded].
  final Widget pageDown;

  /// Page-down chrome show-intent (from [ChatScrollToBottomButton]).
  final bool pageDownVisible;

  /// When true, show search up/down and hide page-down chrome.
  final bool searching;

  /// Composer / keyboard inset.
  final ValueListenable<double>? bottomInset;

  /// Jump to an older search hit (Telegram search-up / flipped chevron).
  final VoidCallback? onSearchUp;

  /// Jump to a newer search hit (Telegram search-down).
  final VoidCallback? onSearchDown;

  /// Optional badge on search-up (hit count).
  final int searchHitCount;

  /// Whether search-up should respond to taps.
  final bool searchUpEnabled;

  /// Whether search-down should respond to taps.
  final bool searchDownEnabled;

  @override
  Widget build(BuildContext context) {
    // Bottom → top: page-down, search-down, search-up (Telegram order).
    return ChatSideControlsStack(
      bottomInset: bottomInset,
      slots: [
        ChatSideControlSlot(
          visible: pageDownVisible && !searching,
          child: pageDown,
        ),
        ChatSideControlSlot(
          visible: searching,
          child: ChatSideControlFab(
            key: const ValueKey<String>('search_down'),
            onTap: searchDownEnabled ? (onSearchDown ?? () {}) : () {},
            semanticLabel: 'Search down',
          ),
        ),
        ChatSideControlSlot(
          visible: searching,
          child: ChatSideControlFab(
            key: const ValueKey<String>('search_up'),
            count: searchHitCount,
            onTap: searchUpEnabled ? (onSearchUp ?? () {}) : () {},
            semanticLabel: 'Search up',
            flipIconY: true,
          ),
        ),
      ],
    );
  }
}
