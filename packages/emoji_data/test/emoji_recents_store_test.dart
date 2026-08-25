import 'package:emoji_data/emoji_data.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('MemoryEmojiRecentsStore', () {
    test('search picks do not update recents', () async {
      final store = MemoryEmojiRecentsStore();
      await store.recordPick('😀', source: EmojiPickSource.grid);
      expect(store.recents, ['😀']);

      final unchanged =
          await store.recordPick('🎉', source: EmojiPickSource.search);
      expect(unchanged, isNull);
      expect(store.recents, ['😀']);
    });

    test('recent pick still records but search does not', () async {
      final store = MemoryEmojiRecentsStore();
      await store.recordPick('😀', source: EmojiPickSource.grid);
      await store.recordPick('🎉', source: EmojiPickSource.recent);
      expect(store.recents.contains('🎉'), isTrue);

      await store.recordPick('🔥', source: EmojiPickSource.search);
      expect(store.recents.contains('🔥'), isFalse);
    });

    test('frequency bumps reorder recents', () async {
      final store = MemoryEmojiRecentsStore();
      await store.recordPick('😀', source: EmojiPickSource.grid);
      await store.recordPick('🎉', source: EmojiPickSource.grid);
      await store.recordPick('🎉', source: EmojiPickSource.grid);
      expect(store.recents.first, '🎉');

      await store.recordPick('😀', source: EmojiPickSource.grid);
      await store.recordPick('😀', source: EmojiPickSource.grid);
      expect(store.recents.first, '😀');
    });

    test('clear empties recents', () async {
      final store = MemoryEmojiRecentsStore();
      await store.recordPick('😀', source: EmojiPickSource.grid);
      await store.clear();
      expect(store.recents, isEmpty);
    });
  });

  group('SharedPrefsEmojiRecentsStore', () {
    const legacyHistoryKey = 'chat_chrome_emoji_use_history';
    const legacyListKey = 'chat_chrome_emoji_recents';

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
    });

    test('loads and persists only on the current history key', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        SharedPrefsEmojiRecentsStore.prefsKey: '😀=2,🎉=1',
        legacyHistoryKey: '💀=9',
        legacyListKey: <String>['👻'],
      });

      final store = SharedPrefsEmojiRecentsStore();
      await store.load();
      expect(store.recents, ['😀', '🎉']);

      await store.recordPick('🔥', source: EmojiPickSource.grid);
      expect(store.recents, ['😀', '🎉', '🔥']);

      final reloaded = SharedPrefsEmojiRecentsStore();
      await reloaded.load();
      expect(reloaded.recents, ['😀', '🎉', '🔥']);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(SharedPrefsEmojiRecentsStore.prefsKey), isTrue);
      expect(prefs.getString(legacyHistoryKey), '💀=9');
      expect(prefs.getStringList(legacyListKey), ['👻']);
    });

    test('ignores legacy history and list keys', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        legacyHistoryKey: '😀=3,🎉=2',
        legacyListKey: <String>['🔥', '💯'],
      });

      final store = SharedPrefsEmojiRecentsStore();
      await store.load();
      expect(store.recents, isEmpty);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(legacyHistoryKey), '😀=3,🎉=2');
      expect(prefs.getStringList(legacyListKey), ['🔥', '💯']);
    });

    test('does not migrate a legacy list into the current key', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        legacyListKey: <String>['🔥', '💯'],
      });

      final store = SharedPrefsEmojiRecentsStore();
      await store.load();
      expect(store.recents, isEmpty);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList(legacyListKey), ['🔥', '💯']);
      expect(
        prefs.containsKey(SharedPrefsEmojiRecentsStore.prefsKey),
        isFalse,
      );
    });

    test('search picks do not update persisted recents', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        SharedPrefsEmojiRecentsStore.prefsKey: '😀=1',
      });

      final store = SharedPrefsEmojiRecentsStore();
      await store.load();

      final unchanged =
          await store.recordPick('🎉', source: EmojiPickSource.search);
      expect(unchanged, isNull);
      expect(store.recents, ['😀']);

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString(SharedPrefsEmojiRecentsStore.prefsKey),
        '😀=1',
      );
    });

    test('clear removes the current history key', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        SharedPrefsEmojiRecentsStore.prefsKey: '😀=1',
      });

      final store = SharedPrefsEmojiRecentsStore();
      await store.load();
      await store.clear();
      expect(store.recents, isEmpty);

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.containsKey(SharedPrefsEmojiRecentsStore.prefsKey),
        isFalse,
      );
    });
  });
}
