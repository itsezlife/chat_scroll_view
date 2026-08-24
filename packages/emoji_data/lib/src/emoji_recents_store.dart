import 'package:emoji_data/src/emoji_pick_source.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Host-owned frequently-used emoji store (frequency map).
abstract class EmojiRecentsStore {
  List<String> get recents;

  Future<List<String>?> recordPick(
    String glyph, {
    required EmojiPickSource source,
  });

  Future<void> clear();
  Future<void> load() async {}
}

/// SharedPreferences-backed frequency recents.
final class SharedPrefsEmojiRecentsStore implements EmojiRecentsStore {
  SharedPrefsEmojiRecentsStore({this.maxCount = 48});

  static const String _prefsKey = 'emoji_data_use_history';
  static const String _legacyKey = 'chat_chrome_emoji_use_history';
  static const String _legacyListKey = 'chat_chrome_emoji_recents';

  final int maxCount;
  SharedPreferences? _prefs;
  final Map<String, int> _useHistory = <String, int>{};
  List<String> _sorted = <String>[];

  @override
  List<String> get recents => List<String>.unmodifiable(_sorted);

  @override
  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    _useHistory
      ..clear()
      ..addAll(_decode(_prefs!.getString(_prefsKey)));
    if (_useHistory.isEmpty) {
      _useHistory.addAll(_decode(_prefs!.getString(_legacyKey)));
    }
    _resort();
    if (_sorted.isEmpty) {
      await _migrateLegacyList();
    }
  }

  Future<void> _migrateLegacyList() async {
    final legacy = _prefs?.getStringList(_legacyListKey);
    if (legacy == null || legacy.isEmpty) return;
    for (final glyph in legacy.reversed) {
      await recordPick(glyph, source: EmojiPickSource.grid);
    }
    await _prefs?.remove(_legacyListKey);
  }

  @override
  Future<List<String>?> recordPick(
    String glyph, {
    required EmojiPickSource source,
  }) async {
    if (source == EmojiPickSource.search) return null;
    if (glyph.isEmpty) return null;

    var count = _useHistory[glyph] ?? 0;
    if (count == 0 && _useHistory.length >= maxCount && _sorted.isNotEmpty) {
      _useHistory.remove(_sorted.last);
    }
    _useHistory[glyph] = count + 1;
    _resort();
    await _persist();
    return List<String>.from(_sorted);
  }

  @override
  Future<void> clear() async {
    if (_useHistory.isEmpty) return;
    _useHistory.clear();
    _sorted = <String>[];
    await _prefs?.remove(_prefsKey);
  }

  void _resort() {
    _sorted = _useHistory.keys.toList(growable: false)
      ..sort((a, b) => (_useHistory[b] ?? 0).compareTo(_useHistory[a] ?? 0));
    if (_sorted.length > maxCount) {
      for (final g in _sorted.sublist(maxCount)) {
        _useHistory.remove(g);
      }
      _sorted = _sorted.sublist(0, maxCount);
    }
  }

  Future<void> _persist() async {
    await _prefs?.setString(_prefsKey, _encode(_useHistory));
  }

  static Map<String, int> _decode(String? raw) {
    final out = <String, int>{};
    if (raw == null || raw.isEmpty) return out;
    for (final entry in raw.split(',')) {
      final i = entry.lastIndexOf('=');
      if (i <= 0) continue;
      final glyph = entry.substring(0, i);
      final count = int.tryParse(entry.substring(i + 1));
      if (count == null || count <= 0) continue;
      out[glyph] = count;
    }
    return out;
  }

  static String _encode(Map<String, int> map) =>
      map.entries.map((e) => '${e.key}=${e.value}').join(',');
}

@visibleForTesting
final class MemoryEmojiRecentsStore implements EmojiRecentsStore {
  MemoryEmojiRecentsStore({this.maxCount = 48});

  final int maxCount;
  final Map<String, int> _useHistory = <String, int>{};
  List<String> _sorted = <String>[];

  @override
  List<String> get recents => List<String>.unmodifiable(_sorted);

  @override
  Future<void> clear() async {
    _useHistory.clear();
    _sorted = <String>[];
  }

  @override
  Future<List<String>?> recordPick(
    String glyph, {
    required EmojiPickSource source,
  }) async {
    if (source == EmojiPickSource.search) return null;
    if (glyph.isEmpty) return null;

    var count = _useHistory[glyph] ?? 0;
    if (count == 0 && _useHistory.length >= maxCount && _sorted.isNotEmpty) {
      _useHistory.remove(_sorted.last);
    }
    _useHistory[glyph] = count + 1;
    _sorted = _useHistory.keys.toList()
      ..sort((a, b) => (_useHistory[b] ?? 0).compareTo(_useHistory[a] ?? 0));
    if (_sorted.length > maxCount) {
      _sorted = _sorted.sublist(0, maxCount);
    }
    return List<String>.from(_sorted);
  }

  @override
  Future<void> load() async {}
}
