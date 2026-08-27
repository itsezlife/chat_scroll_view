import 'dart:async';

import 'package:emoji_data/src/emoji_category_spec.dart';
import 'package:emoji_data/src/emoji_item.dart';
import 'package:emoji_data/src/emoji_pick_source.dart';
import 'package:flutter/foundation.dart';

/// Host-owned emoji catalog, recents, search, and skin-tone prefs.
abstract class EmojiDataSource {
  /// Whether [load] finished and reads are valid.
  bool get isReady;

  /// Categories excluding the synthetic recents section.
  List<EmojiCategorySpec> get categories;

  /// Frequently-used glyphs (most-used first).
  List<String> get recentGlyphs;

  /// Loads catalog, recents, and prefs. Emits [notifyDataChanged] when done.
  Future<void> load();

  /// Keyword search over the loaded catalog.
  FutureOr<List<EmojiItem>> search(String query);

  /// Records a pick when [source] allows it.
  Future<void> recordPick(
    EmojiItem item, {
    required EmojiPickSource source,
  });

  /// Clears frequently-used history.
  Future<void> clearRecents();

  /// Saved skin-tone index for [base] (0 = default).
  int skinToneFor(String base);

  /// Persists skin-tone index for [base]. Index 0 clears.
  Future<void> setSkinTone(String base, int toneIndex);

  void addDataListener(VoidCallback callback);
  void removeDataListener(VoidCallback callback);

  void dispose();
}
