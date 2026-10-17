import 'package:flutter/services.dart';

// The plugin's native code on every platform but the web answers it.
const _channel = MethodChannel('rich_clipboard');

/// Puts [plain] and [html] on the clipboard as one item, replacing what was
/// there.
Future<void> $writeClipboard({required String plain, required String html}) =>
    _channel.invokeMethod<void>('write', {'plain': plain, 'html': html});

/// The clipboard's plain text and HTML, either null when absent; null when it
/// holds neither.
Future<({String? plain, String? html})?> $readClipboard() async {
  final held = await _channel.invokeMapMethod<String, Object?>('read');
  if (held == null) return null;
  return (plain: held['plain'] as String?, html: held['html'] as String?);
}

/// The images and files on the clipboard, each as `bytes` (with a
/// `mimeType`, and a `name` when known) or as a file `path`.
Future<List<Map<Object?, Object?>>> $readClipboardMedia() async {
  final media = await _channel.invokeListMethod<Map<Object?, Object?>>(
    'readMedia',
  );
  return media ?? const [];
}
