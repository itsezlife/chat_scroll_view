import 'dart:developer' as dev;

import 'package:content_model/content_model.dart';
import 'package:flutter/foundation.dart';

/// Whether the user wants a message of nothing but emoji shown large and
/// without a bubble (Telegram's "Large Emoji"), kept in the host's
/// [KeyValueStore] across launches (ADR 023: the host owns persistence).
///
/// On until the user turns it off, as on every reference client. It is only
/// one of the facts the host weighs (`LargeEmojiPolicy`); the setting says
/// what the user prefers, not whether a given message qualifies.
///
/// Created already loaded, like the other stores: [enabled] answers at once,
/// a [set] is reflected by it and notified before its future completes, and
/// the future completes when the choice is saved.
final class LargeEmojiSetting {
  LargeEmojiSetting._(this._storage, {required bool enabled})
    : _enabled = ValueNotifier<bool>(enabled);

  /// The key-value namespace of the record.
  static const String namespace = 'chat_settings';

  /// The key of the record.
  static const String key = 'large_emoji';

  /// The schema version of the record; a record of another version is
  /// ignored.
  static const int version = 1;

  static const String _on = 'on';
  static const String _off = 'off';

  final KeyValueStore _storage;
  final ValueNotifier<bool> _enabled;

  /// The user's choice. [set] changes it.
  ValueListenable<bool> get enabled => _enabled;

  /// Reads the choice from [storage]. A record that is missing, of another
  /// version or unreadable leaves the default, on: a storage that cannot be
  /// reached must not take the feature away.
  static Future<LargeEmojiSetting> load(KeyValueStore storage) async {
    var enabled = true;
    try {
      final stored = await storage.read(namespace, key);
      if (stored != null && stored.version == version) {
        enabled = stored.value != _off;
      }
    } on Object catch (error, stackTrace) {
      dev.log(
        'Reading the large-emoji setting failed',
        name: 'chat_settings',
        error: error,
        stackTrace: stackTrace,
      );
    }
    return LargeEmojiSetting._(storage, enabled: enabled);
  }

  /// Remembers whether the user wants large emoji. Choosing what is already
  /// chosen changes and writes nothing.
  Future<void> set({required bool enabled}) {
    if (_enabled.value == enabled) return Future<void>.value();
    _enabled.value = enabled;
    return _storage.write(
      namespace,
      key,
      StoredValue(enabled ? _on : _off, version: version),
    );
  }

  /// Releases the listeners.
  void dispose() => _enabled.dispose();
}
