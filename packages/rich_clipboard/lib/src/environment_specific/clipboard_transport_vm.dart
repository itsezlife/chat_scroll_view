import 'package:flutter/services.dart';

// The plugin's native code on every platform but the web answers it.
const _channel = MethodChannel('rich_clipboard');

/// Puts [plain] and [html] on the clipboard as one item, replacing what was
/// there.
Future<void> $writeClipboard({required String plain, required String html}) =>
    _channel.invokeMethod<void>('write', {'plain': plain, 'html': html});

/// The clipboard's plain text and HTML, either null when absent, and with
/// [media] its images and files, each as `bytes` (with a `mimeType`, and a
/// `name` when known) or as a file `path`; null when it holds none of them.
/// One read: one access to the clipboard.
Future<({String? plain, String? html, List<Map<Object?, Object?>> media})?>
$readClipboard({required bool media}) async {
  final held = await _channel.invokeMapMethod<String, Object?>('read', {
    'media': media,
  });
  if (held == null) return null;
  return (
    plain: held['plain'] as String?,
    html: held['html'] as String?,
    media: [
      ...?(held['media'] as List<Object?>?)?.cast<Map<Object?, Object?>>(),
    ],
  );
}

/// Flutter delivers a text field's copy, cut and paste to it as intents on
/// every platform but the web: there is nothing to take over.
void Function() $listenClipboardEvents({
  required ({String plain, String html})? Function({required bool cut}) onCopy,
  required bool Function() takesPaste,
  required void Function(
    ({String? plain, String? html, List<Map<Object?, Object?>> media}) held,
  )
  onPaste,
}) => () {};
