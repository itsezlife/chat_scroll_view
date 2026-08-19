import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:flutter/services.dart';

/// Example [ChatPreImeBackNative] over a [MethodChannel].
///
/// [acquire] / [release] toggle the Activity intercept. Incoming `onBack`
/// is forwarded to [ChatPreImeBackBinding.handleNativeBack]. A missing
/// native implementation (desktop, tests) is a no-op so Dart overlay
/// back still works.
final class ExamplePreImeBackNative implements ChatPreImeBackNative {
  /// Creates an adapter on [channel].
  ExamplePreImeBackNative({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_kExamplePreImeBackChannel) {
    _channel.setMethodCallHandler(_onMethodCall);
  }

  static const String _kExamplePreImeBackChannel =
      'chat_scroll_view_example/pre_ime_back';

  final MethodChannel _channel;

  @override
  Future<void> acquire() => _invoke('acquire');

  @override
  Future<void> release() => _invoke('release');

  Future<void> _invoke(String method) async {
    try {
      await _channel.invokeMethod<void>(method);
    } on MissingPluginException {
      // Desktop / tests: overlay back remains.
    }
  }

  Future<bool> _onMethodCall(MethodCall call) async {
    if (call.method == 'onBack') {
      return ChatPreImeBackBinding.handleNativeBack();
    }
    throw MissingPluginException(call.method);
  }
}

/// Assigns [ChatPreImeBackBinding.native] for this example.
void bindExamplePreImeBack() =>
    ChatPreImeBackBinding.native = ExamplePreImeBackNative();
