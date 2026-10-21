import 'dart:async';

import 'package:chat_scroll_view/chat_scroll_view.dart'
    show ChatEmojiPolicy, ChatEmojiPolicy$Desktop;
import 'package:chat_scroll_view_example/src/features/chat/data/large_emoji_setting.dart';
import 'package:flutter/material.dart';

/// The menu that moves how many regular emoji a message may hold and still be
/// enlarged, next to the large-emoji toggle.
///
/// Only the desktop family (and the web) has a cap, so the button is nothing
/// elsewhere: Android and iOS enlarge a run of any length, and a control that
/// did nothing there would be a lie.
class LargeEmojiLimitButton extends StatelessWidget {
  /// Creates the button over [setting].
  const LargeEmojiLimitButton({required this.setting, super.key});

  /// Where the cap is kept.
  final LargeEmojiSetting setting;

  @override
  Widget build(BuildContext context) {
    if (ChatEmojiPolicy.forPlatform() is! ChatEmojiPolicy$Desktop) {
      return const SizedBox.shrink();
    }
    return ValueListenableBuilder<int>(
      valueListenable: setting.desktopLimit,
      builder: (context, limit, _) => PopupMenuButton<int>(
        tooltip: 'Large emoji: up to $limit regular emoji',
        initialValue: limit,
        onSelected: (choice) => unawaited(setting.setDesktopLimit(choice)),
        itemBuilder: (context) => [
          for (final choice in LargeEmojiSetting.desktopLimitChoices)
            PopupMenuItem<int>(value: choice, child: Text('$choice')),
        ],
        icon: const Icon(Icons.format_list_numbered, size: 20),
      ),
    );
  }
}
