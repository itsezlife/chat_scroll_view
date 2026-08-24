import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

/// Persists per-base skin-tone preferences.
abstract class SkinTonePrefs {
  int toneFor(String base);
  Future<void> setTone(String base, int toneIndex);
  Future<void> load();
}

/// SharedPreferences-backed skin-tone map.
final class SharedPrefsSkinTonePrefs implements SkinTonePrefs {
  static const String _colorsKey = 'chat_chrome_emoji_colors';

  SharedPreferences? _prefs;
  final Map<String, int> _tones = <String, int>{};

  @override
  int toneFor(String base) => _tones[base] ?? 0;

  @override
  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    _tones
      ..clear()
      ..addAll(_decode(_prefs!.getStringList(_colorsKey)));
  }

  @override
  Future<void> setTone(String base, int toneIndex) async {
    if (toneIndex <= 0) {
      if (!_tones.containsKey(base)) return;
      _tones.remove(base);
    } else {
      if (_tones[base] == toneIndex) return;
      _tones[base] = toneIndex;
    }
    await _prefs?.setStringList(_colorsKey, _encode(_tones));
  }

  static Map<String, int> _decode(List<String>? raw) {
    final out = <String, int>{};
    if (raw == null) return out;
    for (final entry in raw) {
      final i = entry.lastIndexOf('=');
      if (i <= 0) continue;
      final tone = int.tryParse(entry.substring(i + 1));
      if (tone == null || tone < 1 || tone > 5) continue;
      out[entry.substring(0, i)] = tone;
    }
    return out;
  }

  static List<String> _encode(Map<String, int> map) =>
      map.entries.map((e) => '${e.key}=${e.value}').toList(growable: false);
}

@visibleForTesting
final class MemorySkinTonePrefs implements SkinTonePrefs {
  final Map<String, int> _tones = <String, int>{};

  @override
  int toneFor(String base) => _tones[base] ?? 0;

  @override
  Future<void> load() async {}

  @override
  Future<void> setTone(String base, int toneIndex) async {
    if (toneIndex <= 0) {
      _tones.remove(base);
    } else {
      _tones[base] = toneIndex;
    }
  }
}
