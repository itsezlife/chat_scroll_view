import 'dart:developer' as dev;

import 'package:chat_scroll_view/chat_scroll_view.dart'
    show ChatEmojiPolicy$Desktop;
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
/// On desktop it also keeps the cap on enlarged regular emoji
/// ([desktopLimit], the reference client's 3 until moved): a record of its
/// own, so the on/off choice and the cap never overwrite each other. The
/// other families have no cap and never read it.
///
/// Created already loaded, like the other stores: [enabled] answers at once,
/// a [set] is reflected by it and notified before its future completes, and
/// the future completes when the choice is saved.
final class LargeEmojiSetting {
  LargeEmojiSetting._(
    this._storage, {
    required bool enabled,
    required int desktopLimit,
  }) : _enabled = ValueNotifier<bool>(enabled),
       _desktopLimit = ValueNotifier<int>(desktopLimit);

  /// The key-value namespace of the record.
  static const String namespace = 'chat_settings';

  /// The key of the record.
  static const String key = 'large_emoji';

  /// The schema version of the record; a record of another version is
  /// ignored.
  static const int version = 1;

  /// The key of the desktop cap's record, in the same [namespace].
  static const String desktopLimitKey = 'large_emoji_desktop_limit';

  /// The cap until the user moves it: the reference client's.
  static const int defaultDesktopLimit =
      ChatEmojiPolicy$Desktop.defaultRegularLimit;

  /// The largest cap the setting keeps. Beyond it "enlarged" would mean every
  /// message; the example offers a few steps of it.
  static const int maxDesktopLimit = 20;

  /// The steps the example offers; any whole number up to [maxDesktopLimit]
  /// is kept.
  static const List<int> desktopLimitChoices = [1, 2, 3, 5, 8, 10, 20];

  static const String _on = 'on';
  static const String _off = 'off';

  final KeyValueStore _storage;
  final ValueNotifier<bool> _enabled;
  final ValueNotifier<int> _desktopLimit;

  /// The user's choice. [set] changes it.
  ValueListenable<bool> get enabled => _enabled;

  /// How many regular emoji a message may hold and still be enlarged on
  /// desktop; [setDesktopLimit] changes it.
  ValueListenable<int> get desktopLimit => _desktopLimit;

  /// Reads the choice from [storage]. A record that is missing, of another
  /// version or unreadable leaves the default, on: a storage that cannot be
  /// reached must not take the feature away.
  static Future<LargeEmojiSetting> load(KeyValueStore storage) async {
    var enabled = true;
    var desktopLimit = defaultDesktopLimit;
    try {
      final stored = await storage.read(namespace, key);
      if (stored != null && stored.version == version) {
        enabled = stored.value != _off;
      }
      final cap = await storage.read(namespace, desktopLimitKey);
      if (cap != null && cap.version == version) {
        // A record that is not a whole number within range is the default,
        // not a clamp: it was never a choice this setting wrote.
        final parsed = int.tryParse(cap.value);
        if (parsed != null && parsed >= 1 && parsed <= maxDesktopLimit) {
          desktopLimit = parsed;
        }
      }
    } on Object catch (error, stackTrace) {
      dev.log(
        'Reading the large-emoji setting failed',
        name: 'chat_settings',
        error: error,
        stackTrace: stackTrace,
      );
    }
    return LargeEmojiSetting._(
      storage,
      enabled: enabled,
      desktopLimit: desktopLimit,
    );
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

  /// Remembers the desktop cap: [limit] regular emoji, from 1 to
  /// [maxDesktopLimit]. Choosing what is already chosen changes and writes
  /// nothing.
  Future<void> setDesktopLimit(int limit) {
    RangeError.checkValueInInterval(limit, 1, maxDesktopLimit, 'limit');
    if (_desktopLimit.value == limit) return Future<void>.value();
    _desktopLimit.value = limit;
    return _storage.write(
      namespace,
      desktopLimitKey,
      StoredValue('$limit', version: version),
    );
  }

  /// Releases the listeners.
  void dispose() {
    _enabled.dispose();
    _desktopLimit.dispose();
  }
}
