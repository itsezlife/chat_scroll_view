import 'package:chat_scroll_view_example/src/features/chat/data/chat_draft_store.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeKeyValueStore storage;

  setUp(() => storage = FakeKeyValueStore());

  test(
    'a draft reads back per chat and survives reopening the store',
    () async {
      final store = ChatDraftStore(storage);
      const draft = ChatDraft(markdown: 'hi **there**\n\nsecond line  ');

      await store.write('backend.1', draft);

      expect(await store.read('backend.1'), draft);
      expect(await store.read('comments'), isNull);
      expect(await ChatDraftStore(storage).read('backend.1'), draft);
    },
  );

  test('the message being edited is stored beside the markdown', () async {
    final store = ChatDraftStore(storage);
    const draft = ChatDraft(markdown: 'edited', editing: 17);

    await store.write('comments', draft);

    expect(await ChatDraftStore(storage).read('comments'), draft);
    expect(draft, isNot(const ChatDraft(markdown: 'edited')));
  });

  test(
    'a markdown body that holds line breaks and digits reads back whole',
    () async {
      final store = ChatDraftStore(storage);
      const draft = ChatDraft(markdown: '12\n34\n\n', editing: 5);

      await store.write('comments', draft);

      expect(await ChatDraftStore(storage).read('comments'), draft);
    },
  );

  test('writing null removes the stored key', () async {
    final store = ChatDraftStore(storage);
    await store.write('comments', const ChatDraft(markdown: 'x'));

    await store.write('comments', null);

    expect(await storage.read(ChatDraftStore.namespace, 'comments'), isNull);
    expect(await ChatDraftStore(storage).read('comments'), isNull);
  });

  test('a write is readable before its future completes', () async {
    final store = ChatDraftStore(storage);

    final pending = store.write('comments', const ChatDraft(markdown: 'x'));

    expect(await store.read('comments'), const ChatDraft(markdown: 'x'));
    await pending;
  });

  test('a record of another version or shape counts as no draft', () async {
    await storage.write(
      ChatDraftStore.namespace,
      'comments',
      const StoredValue('\nx', version: ChatDraftStore.version + 1),
    );
    await storage.write(
      ChatDraftStore.namespace,
      'backend.1',
      const StoredValue('no header line', version: ChatDraftStore.version),
    );
    await storage.write(
      ChatDraftStore.namespace,
      'backend.2',
      const StoredValue('abc\nx', version: ChatDraftStore.version),
    );

    expect(await ChatDraftStore(storage).read('comments'), isNull);
    expect(await ChatDraftStore(storage).read('backend.1'), isNull);
    expect(await ChatDraftStore(storage).read('backend.2'), isNull);
  });
}
