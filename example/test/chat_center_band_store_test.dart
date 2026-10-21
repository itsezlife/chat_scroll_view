import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/chat_center_band_store.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const band = ChatCenterBand(messageId: 42, offsetFromMessageTop: 17.5);

  late FakeKeyValueStore storage;

  setUp(() => storage = FakeKeyValueStore());

  test('a saved Center Band reads back per chat and survives reopening the '
      'store', () async {
    final store = ChatCenterBandStore(storage);
    expect(await store.read('comments'), isNull);

    await store.write('comments', band);

    expect(await store.read('comments'), band);
    expect(await store.read('backend.1'), isNull);
    expect(await ChatCenterBandStore(storage).read('comments'), band);
  });

  test('writing null drops only that chat', () async {
    final store = ChatCenterBandStore(storage);
    await store.write('comments', band);
    await store.write('backend.1', band);

    await store.write('comments', null);

    expect(await store.read('comments'), isNull);
    expect(await store.read('backend.1'), band);
  });

  test('a write is readable before its future completes', () async {
    final store = ChatCenterBandStore(storage);

    final pending = store.write('comments', band);

    expect(await store.read('comments'), band);
    await pending;
  });

  test('a record the store cannot read counts as no saved position', () async {
    await storage.write(
      ChatCenterBandStore.namespace,
      'comments',
      const StoredValue('not a band', version: ChatCenterBandStore.version),
    );
    await storage.write(
      ChatCenterBandStore.namespace,
      'backend.1',
      const StoredValue('42:17.5', version: ChatCenterBandStore.version + 1),
    );

    expect(await ChatCenterBandStore(storage).read('comments'), isNull);
    expect(await ChatCenterBandStore(storage).read('backend.1'), isNull);
  });

  test('a chat key outside the key-value name alphabet is refused', () async {
    final store = ChatCenterBandStore(storage);

    await expectLater(store.read('backend/1'), throwsArgumentError);
  });
}
