import 'dart:convert';

import 'package:chat_composer/chat_composer.dart';
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
      const StoredValue(
        'no header line',
        version: ChatDraftStore.legacyVersion,
      ),
    );
    await storage.write(
      ChatDraftStore.namespace,
      'backend.2',
      const StoredValue('abc\nx', version: ChatDraftStore.legacyVersion),
    );

    expect(await ChatDraftStore(storage).read('comments'), isNull);
    expect(await ChatDraftStore(storage).read('backend.1'), isNull);
    expect(await ChatDraftStore(storage).read('backend.2'), isNull);
  });

  group('link preview fields', () {
    final url = Uri.parse('https://a.example/x');

    test('the options, invertMedia and the dismissal read back', () async {
      final draft = ChatDraft(
        markdown: 'see https://a.example/x',
        editing: 3,
        linkPreview: ChatLinkPreviewDraft(
          options: LinkPreviewOptions(url: url, media: LinkPreviewMedia.large),
          invertMedia: true,
          dismissal: LinkPreviewDismissalState(
            policy: LinkPreviewDismissalPolicy.perUrl,
            disabledUrls: {Uri.parse('https://b.example/')},
          ),
        ),
      );

      await ChatDraftStore(storage).write('comments', draft);

      expect(await ChatDraftStore(storage).read('comments'), draft);
    });

    test('the record is one object with the wire field names', () async {
      await ChatDraftStore(storage).write(
        'comments',
        ChatDraft(
          markdown: 'x',
          linkPreview: ChatLinkPreviewDraft(
            options: LinkPreviewOptions(url: url),
          ),
        ),
      );

      final stored = await storage.read(ChatDraftStore.namespace, 'comments');
      expect(stored?.version, ChatDraftStore.version);
      expect(jsonDecode(stored!.value), {
        'body': 'x',
        'linkPreview': {
          'url': 'https://a.example/x',
          'media': 'auto',
          'removed': false,
        },
      });
    });

    test('a record of the first version reads as its text', () async {
      await storage.write(
        ChatDraftStore.namespace,
        'comments',
        const StoredValue('7\nold **text**', version: 1),
      );

      expect(
        await ChatDraftStore(storage).read('comments'),
        const ChatDraft(markdown: 'old **text**', editing: 7),
      );
    });

    test('a stored plain string reads as the body alone', () async {
      await storage.write(
        ChatDraftStore.namespace,
        'comments',
        const StoredValue('just *text*', version: ChatDraftStore.version),
      );

      expect(
        await ChatDraftStore(storage).read('comments'),
        const ChatDraft(markdown: 'just *text*'),
      );
    });

    test('an object without a body is no draft, and says so', () async {
      final diagnostics = RecordingDiagnostics.install();
      await storage.write(
        ChatDraftStore.namespace,
        'comments',
        const StoredValue('{"editing": 3}', version: ChatDraftStore.version),
      );

      expect(await ChatDraftStore(storage).read('comments'), isNull);
      expect(diagnostics.whereOp(ChatDraftOp.draftDecodeFailed), [
        isChatEvent(
          level: ChatEventLevel.warning,
          category: ChatEventCategory.linkPreview,
          correlation: const ChatCorrelation(chatId: 'comments'),
          fields: {'errorType': 'noBody'},
        ),
      ]);
    });
  });
}
