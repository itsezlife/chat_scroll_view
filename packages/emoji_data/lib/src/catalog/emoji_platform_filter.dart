import 'dart:async';

import 'package:emoji_data/src/emoji_item.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Method channel shared with native [EmojiDataPlugin] implementations.
abstract final class EmojiPlatformFilters {
  /// Channel name registered by the emoji_data plugin on each platform.
  static const methodChannelName = 'emoji_data';

  /// Host-side glyph filter when [enabled]; otherwise no-op.
  static EmojiPlatformFilter create({required bool enabled}) {
    if (!enabled) return PassthroughEmojiPlatformFilter();
    return NativeEmojiPlatformFilter();
  }
}

/// Filters glyphs unsupported on the host platform (Android IME font set).
abstract class EmojiPlatformFilter {
  /// Returns [items] unchanged when filtering is unavailable.
  FutureOr<List<UnicodeEmojiItem>> filter(List<UnicodeEmojiItem> items);
}

/// No-op filter — used in tests and when filtering is disabled.
final class PassthroughEmojiPlatformFilter implements EmojiPlatformFilter {
  @override
  FutureOr<List<UnicodeEmojiItem>> filter(List<UnicodeEmojiItem> items) =>
      items;
}

/// Queries native code for per-glyph support via [EmojiPlatformFilters.methodChannelName].
final class NativeEmojiPlatformFilter implements EmojiPlatformFilter {
  NativeEmojiPlatformFilter({MethodChannel? channel})
    : _channel =
          channel ?? const MethodChannel(EmojiPlatformFilters.methodChannelName);

  final MethodChannel _channel;

  static final Map<String, bool> _supportCache = <String, bool>{};

  @override
  FutureOr<List<UnicodeEmojiItem>> filter(List<UnicodeEmojiItem> items) {
    final unknown = items.where((e) => !_supportCache.containsKey(e.glyph));
    if (unknown.isEmpty) {
      return items.where((e) => _supportCache[e.glyph] ?? false).toList();
    }

    return _queryAndFilter(items, unknown.toList(growable: false));
  }

  Future<List<UnicodeEmojiItem>> _queryAndFilter(
    List<UnicodeEmojiItem> items,
    List<UnicodeEmojiItem> unknown,
  ) async {
    try {
      final glyphs = unknown.map((e) => e.glyph).toList(growable: false);
      final supported = await _channel.invokeListMethod<bool>(
        'getSupportedEmojis',
        {'source': glyphs},
      );
      if (supported != null && supported.length == glyphs.length) {
        for (var i = 0; i < glyphs.length; i++) {
          _supportCache[glyphs[i]] = supported[i];
        }
      }
    } on MissingPluginException {
      return items;
    } on PlatformException {
      return items;
    }

    return items.where((e) => _supportCache[e.glyph] ?? true).toList();
  }

  @visibleForTesting
  static void resetCacheForTests() => _supportCache.clear();
}
