import 'dart:ui' as ui;

import 'package:flutter/services.dart';

/// The app's binary messenger with the text processing actions query
/// answered once per app run, for every text field: this package's and the
/// stock `EditableText`s, which query on every mount and have no hook to
/// share an answer.
///
/// On Android the query is a package manager lookup run on the platform
/// thread, which is the UI thread: tens of milliseconds warm, more than a
/// hundred cold, and a field that mounts (a search field after a page
/// switch) freezes the frame it shows in. The actions are the device's text
/// processing apps, which an app run does not see change, so the first answer
/// is every later one's. Queries in flight together share the one call; a
/// call that fails is asked again by the next query. Every other message, the
/// processing of a text among them, passes through.
///
/// A host installs it as its binding's messenger
/// (`ServicesBinding.createBinaryMessenger`), so the first query (a prefetch
/// at an idle moment, or the first field) is the only one the platform sees.
final class ProcessTextQueryCache extends BinaryMessenger {
  /// The messenger of the platform, [platform], with the query cached.
  ProcessTextQueryCache(this.platform);

  /// The messenger every message goes on to.
  final BinaryMessenger platform;

  Future<ByteData?>? _actions;

  static const _queryMethod = 'ProcessText.queryTextActions';

  @override
  Future<ByteData?>? send(String channel, ByteData? message) {
    if (!_isQuery(channel, message)) return platform.send(channel, message);
    if (_actions case final actions?) return actions;
    final reply = platform.send(channel, message);
    if (reply == null) return null;
    _actions = reply;
    // A failed call is not the answer: the next query asks again.
    reply.then<void>(
      (_) {},
      onError: (Object _) {
        if (identical(_actions, reply)) _actions = null;
      },
    );
    return reply;
  }

  static bool _isQuery(String channel, ByteData? message) {
    if (channel != SystemChannels.processText.name || message == null) {
      return false;
    }
    try {
      return SystemChannels.processText.codec
              .decodeMethodCall(message)
              .method ==
          _queryMethod;
    } on FormatException {
      return false;
    }
  }

  @override
  void setMessageHandler(String channel, MessageHandler? handler) =>
      platform.setMessageHandler(channel, handler);

  @override
  @Deprecated(
    'Instead of calling this method, use '
    'ServicesBinding.instance.channelBuffers.push.',
  )
  Future<void> handlePlatformMessage(
    String channel,
    ByteData? data,
    ui.PlatformMessageResponseCallback? callback,
  ) =>
      // The messenger is a pass-through for everything but the query.
      // ignore: deprecated_member_use
      platform.handlePlatformMessage(channel, data, callback);
}
