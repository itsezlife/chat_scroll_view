import 'package:emoji_data/emoji_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('search picks do not update recents', () async {
    final store = MemoryEmojiRecentsStore();
    await store.recordPick('😀', source: EmojiPickSource.grid);
    expect(store.recents, ['😀']);

    final unchanged = await store.recordPick('🎉', source: EmojiPickSource.search);
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
}
