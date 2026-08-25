import 'package:emoji_data/src/emoji_pick_source.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Host-owned frequently-used emoji frequency map.
abstract class EmojiRecentsStore {
  /// Frequency-sorted glyphs (highest use first). Unmodifiable view.
  List<String> get recents;

  /// Records a qualifying pick and returns the new ordered list, or `null`
  /// when the pick is ignored ([EmojiPickSource.search] / empty glyph).
  Future<List<String>?> recordPick(
    String glyph, {
    required EmojiPickSource source,
  });

  /// Wipes the frequency map. No-op when already empty.
  Future<void> clear();

  /// Hydrates from durable storage when the implementation persists.
  ///
  /// Default is a no-op (in-memory stores).
  Future<void> load() async {}
}

/// SharedPreferences-backed frequency recents.
///
/// ## Persistence
///
/// Reads and writes only [prefsKey] (`emoji_data_use_history`). Encoded form
/// is `glyph=count` entries joined by commas. Absent or empty [prefsKey] data
/// yields an empty map; other prefs keys are ignored.
///
/// ## Ordering and caps
///
/// Recents are sorted by descending use count. When inserting a new glyph at
/// [maxCount], the lowest-frequency entry is evicted first. [clear] removes
/// the prefs entry; it does not touch unrelated keys.
///
/// ## Silent paths
///
/// [recordPick] with [EmojiPickSource.search] or an empty glyph returns `null`
/// and leaves prefs unchanged. [clear] returns without writing when already
/// empty. [load] must run before [recordPick] / [clear] persist — until then
/// `_prefs` is null and writes are skipped.
final class SharedPrefsEmojiRecentsStore implements EmojiRecentsStore {
  SharedPrefsEmojiRecentsStore({this.maxCount = 48});

  /// Durable frequency-map key. Sole load/persist identity for this store.
  @visibleForTesting
  static const String prefsKey = 'emoji_data_use_history';

  /// Maximum glyphs retained. New inserts at capacity evict the lowest count.
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
      ..addAll(_decode(_prefs!.getString(prefsKey)));
    _resort();
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
    await _prefs?.remove(prefsKey);
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
    await _prefs?.setString(prefsKey, _encode(_useHistory));
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

/// In-memory frequency recents for tests and hosts that skip persistence.
///
/// Same pick / clear / search-ignore contracts as [SharedPrefsEmojiRecentsStore]
/// without SharedPreferences. [load] is a no-op.
@visibleForTesting
final class MemoryEmojiRecentsStore implements EmojiRecentsStore {
  MemoryEmojiRecentsStore({this.maxCount = 48});

  /// Maximum glyphs retained. New inserts at capacity evict the lowest count.
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
