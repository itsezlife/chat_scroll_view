import 'package:chat_scroll_view_example/src/features/chat/utils/chat_copy_feedback.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _channel = MethodChannel('chat_scroll_view_example/system');

/// Whether the platform shows its own clipboard toast after a copy: only an
/// Android system that does, per [ChatCopyFeedback.androidSystemConfirms].
///
/// False when the platform channel is missing (widget tests, other hosts).
Future<bool> systemConfirmsCopy() async {
  if (defaultTargetPlatform != TargetPlatform.android) return false;
  try {
    final info = await _channel.invokeMapMethod<String, Object?>(
      'clipboardToast',
    );
    if (info == null) return false;
    return ChatCopyFeedback.androidSystemConfirms(
      sdkInt: info['sdkInt']! as int,
      hasBuiltInClipboardToasts: info['oneUi40']! as bool,
    );
  } on MissingPluginException {
    return false;
  }
}
