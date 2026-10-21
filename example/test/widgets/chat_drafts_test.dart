/// The composer's unsent text surviving a chat being left and opened again.
///
/// Drives the real [ChatInputSet] over an in-memory [KeyValueStore]; leaving
/// a chat is the screen being replaced, opening it is a new rig over the same
/// storage.
library;

import 'package:chat_scroll_view_example/src/app/app_services.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/chat_draft_store.dart';
import 'package:chat_scroll_view_example/src/features/chat/input/chat_composer_spec.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter/widgets.dart' show SizedBox;
import 'package:flutter_test/flutter_test.dart';

import '../support/input_harness.dart';
import '../support/test_services.dart';

const _chat = 'backend.1';

/// The draft debounce, with room to spare.
const _debounce = Duration(seconds: 1);

late FakeKeyValueStore _storage;
late AppServices _services;

Future<InputRig> _open(WidgetTester tester) async {
  final rig = await InputRig.pump(tester, services: _services);
  await rig.set.bindDrafts(_services.drafts, _chat);
  await tester.pump();
  return rig;
}

/// Leaves the chat: its screen goes away and the set with it.
Future<void> _leave(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
}

Future<ChatDraft?> _stored() => ChatDraftStore(_storage).read(_chat);

RichText get _loud =>
    RichText('make it loud', const [Entity(8, 4, EntityKind.bold)]);

void main() {
  setUp(() => _storage = FakeKeyValueStore());

  Future<void> boot(WidgetTester tester) async {
    _services = (await tester.runAsync(
      () => createTestServices(storage: _storage),
    ))!;
    addTearDown(_services.dispose);
  }

  group('drafts', () {
    testWidgets('typing, leaving and reopening restores the text with its '
        'entities', (tester) async {
      await boot(tester);
      var rig = await _open(tester);
      rig.set.composer.restore(_loud);
      await tester.pump();

      await _leave(tester);
      rig = await _open(tester);

      expect(rig.set.composer.richText, _loud);
      expect(rig.set.editing.value, isNull);
    });

    testWidgets('a link, a mention and a quote come back too', (tester) async {
      await boot(tester);
      var rig = await _open(tester);
      final draft = RichText('docs @Ann\nquoted', const [
        Entity(0, 4, EntityKind.link('https://flutter.dev')),
        Entity(5, 4, EntityKind.mention('7')),
        Entity(10, 6, EntityKind.quote),
      ]);
      rig.set.composer.restore(draft);
      await tester.pump();

      await _leave(tester);
      rig = await _open(tester);

      expect(rig.set.composer.richText, draft);
    });

    testWidgets('are written after the debounce, not on each change', (
      tester,
    ) async {
      await boot(tester);
      final rig = await _open(tester);

      rig.set.composer.insertText('a');
      await tester.pump(const Duration(milliseconds: 100));
      rig.set.composer.insertText('b');
      await tester.pump(const Duration(milliseconds: 100));
      expect(_storage.entries, isEmpty);

      await tester.pump(_debounce);
      expect(await _stored(), const ChatDraft(markdown: 'ab'));
      expect(_storage.writeCount, 1);
    });

    testWidgets('leaving at once still saves what was typed', (tester) async {
      await boot(tester);
      final rig = await _open(tester);

      rig.set.composer.insertText('typed last second');
      await _leave(tester);

      expect(await _stored(), const ChatDraft(markdown: 'typed last second'));
    });

    testWidgets('sending clears the stored key', (tester) async {
      await boot(tester);
      final rig = await _open(tester);
      rig.set.composer.insertText('hello');
      await tester.pump(_debounce);
      expect(await _stored(), isNotNull);

      await rig.tapAction(tester, ChatComposerActions.primary);
      await tester.pump();

      expect(rig.sent, ['hello']);
      expect(_storage.entries, isEmpty);

      // The composer emptied by the send writes nothing back.
      await tester.pump(_debounce);
      expect(_storage.entries, isEmpty);
    });

    testWidgets('an emptied composer leaves no draft', (tester) async {
      await boot(tester);
      final rig = await _open(tester);
      rig.set.composer.insertText('x');
      await tester.pump(_debounce);

      rig.set.composer.clear();
      await tester.pump(_debounce);

      expect(_storage.entries, isEmpty);
    });

    testWidgets('an edit in progress restores into edit mode for the same '
        'message', (tester) async {
      await boot(tester);
      var rig = await _open(tester);
      rig.set.beginEdit(17, 'make it **loud**');
      rig.set.composer.insertText('!');
      await tester.pump();

      await _leave(tester);
      expect(
        await _stored(),
        const ChatDraft(markdown: 'make it **loud**!', editing: 17),
      );
      rig = await _open(tester);

      expect(rig.set.editing.value?.id, 17);
      expect(rig.set.composer.text.text, 'make it loud!');
      expect(rig.set.composer.richText.entities, const [
        Entity(8, 4, EntityKind.bold),
      ]);

      await rig.tapAction(tester, ChatComposerActions.primary);
      await tester.pump();
      expect(rig.edited, ['17:make it **loud**!']);
      expect(_storage.entries, isEmpty);
    });

    testWidgets('cancelling an edit does not leave the edit draft behind', (
      tester,
    ) async {
      await boot(tester);
      final rig = await _open(tester);
      rig.set.beginEdit(17, 'text');
      await tester.pump(_debounce);
      expect(await _stored(), const ChatDraft(markdown: 'text', editing: 17));

      rig.set.cancelEdit();
      await tester.pump(_debounce);

      expect(_storage.entries, isEmpty);
    });

    testWidgets('text typed before the stored draft was read wins over it', (
      tester,
    ) async {
      await boot(tester);
      await ChatDraftStore(
        _storage,
      ).write(_chat, const ChatDraft(markdown: 'old'));
      final rig = await InputRig.pump(tester, services: _services);
      rig.set.composer.insertText('new');

      await rig.set.bindDrafts(_services.drafts, _chat);
      await tester.pump(_debounce);

      expect(rig.set.composer.text.text, 'new');
      expect(await _stored(), const ChatDraft(markdown: 'new'));
    });

    testWidgets('a store that fails does not break the composer', (
      tester,
    ) async {
      await boot(tester);
      final rig = await _open(tester);
      _storage.failure = Exception('disk full');

      rig.set.composer.insertText('still typing');
      await tester.pump(_debounce);
      await tester.pump();

      expect(rig.set.composer.text.text, 'still typing');
      expect(tester.takeException(), isNull);
    });

    testWidgets('a draft is kept per chat', (tester) async {
      await boot(tester);
      final rig = await _open(tester);
      rig.set.composer.insertText('for chat one');
      await _leave(tester);

      final other = await InputRig.pump(tester, services: _services);
      await other.set.bindDrafts(_services.drafts, 'comments');
      await tester.pump();

      expect(other.set.composer.text.text, isEmpty);
    });
  });
}
