import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/chat_center_band_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const band = ChatCenterBand(messageId: 42, offsetFromMessageTop: 17.5);

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('a saved Center Band reads back per chat and survives reopening the '
      'store', () async {
    final store = await ChatCenterBandStore.open();
    expect(store.read('comments'), isNull);

    await store.write('comments', band);

    expect(store.read('comments'), band);
    expect(store.read('backend/1'), isNull);
    expect((await ChatCenterBandStore.open()).read('comments'), band);
  });

  test('writing null drops only that chat', () async {
    final store = await ChatCenterBandStore.open();
    await store.write('comments', band);
    await store.write('backend/1', band);

    await store.write('comments', null);

    expect(store.read('comments'), isNull);
    expect(store.read('backend/1'), band);
  });

  test('a write is readable before its future completes', () async {
    final store = await ChatCenterBandStore.open();

    final pending = store.write('comments', band);

    expect(store.read('comments'), band);
    await pending;
  });
}
