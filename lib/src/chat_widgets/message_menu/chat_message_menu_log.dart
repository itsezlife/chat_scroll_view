import 'dart:developer' as dev;

import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_dev_log.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// Message-menu diagnostics. Filter the console by `ChatMessageMenu`.
///
/// Enabled in debug so a device/session log can be copied back. Set
/// [enabled] to `false` to silence.
final ChatScrollDevLog chatMessageMenuLog = ChatScrollDevLog(
  'ChatMessageMenu',
  enabled: true,
);

/// Formats geometry for [chatMessageMenuLog] field maps.
abstract final class ChatMessageMenuLogFormat {
  /// `l,t,w×h` for a rect.
  static String rect(Rect r) =>
      '${DevLogFormat.f(r.left)},${DevLogFormat.f(r.top)},'
      '${DevLogFormat.f(r.width)}×${DevLogFormat.f(r.height)}';

  /// `x,y` for an offset.
  static String offset(Offset o) =>
      '${DevLogFormat.f(o.dx)},${DevLogFormat.f(o.dy)}';

  /// `w×h` for a size.
  static String size(Size s) =>
      '${DevLogFormat.f(s.width)}×${DevLogFormat.f(s.height)}';

  /// `l,t,r,b` insets.
  static String insets(EdgeInsets e) =>
      '${DevLogFormat.f(e.left)},${DevLogFormat.f(e.top)},'
      '${DevLogFormat.f(e.right)},${DevLogFormat.f(e.bottom)}';
}

/// Emits one menu log line. Also [debugPrint]s so the Run console is copyable.
void logChatMessageMenu(String tag, Map<String, Object?> fields) {
  chatMessageMenuLog.event(tag, fields);
  if (!kDebugMode || !chatMessageMenuLog.enabled) return;
  final body = fields.entries
      .where((e) => e.value != null)
      .map((e) => '${e.key}=${e.value}')
      .join(' ');
  dev.log('$tag | $body', name: 'ChatMessageMenu');
}
