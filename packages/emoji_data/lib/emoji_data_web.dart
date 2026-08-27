import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';

/// Web registrar for [EmojiDataPlugin] method-channel handlers.
class EmojiDataWeb {
  /// Registers the web implementation.
  static void registerWith(Registrar registrar) {
    final channel = MethodChannel(
      'emoji_data',
      const StandardMethodCodec(),
      registrar,
    );
    channel.setMethodCallHandler(_handleMethodCall);
  }

  static Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'getSupportedEmojis':
        final args = call.arguments! as Map<Object?, Object?>;
        final source = (args['source'] as List<Object?>).cast<String>();
        return List<bool>.filled(source.length, true);
      default:
        throw MissingPluginException('${call.method} is not implemented');
    }
  }
}
