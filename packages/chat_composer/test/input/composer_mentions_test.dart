/// Mention trust on the send path: a `Mention(id)` the host did not resolve in
/// this draft is rewritten to the `@name` it displays before the text is
/// encoded.
///
/// **Seam:** [ComposerController.sendableText] and
/// [downgradeUnresolvedMentions], observed through the rich text they return.
library;

import 'package:chat_composer/chat_composer.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/markdown.dart';
import 'package:content_model/testing.dart';
import 'package:flutter/widgets.dart' hide RichText;
import 'package:flutter_test/flutter_test.dart';

const _mentionQuery = ComposerQueryKind(id: 'mention', trigger: '@');

/// "hi @alice!" with a mention of [id] over "@alice".
RichText _hiAlice(String id) =>
    RichText('hi @alice!', [Entity(3, 6, EntityKind.mention(id))]);

void main() {
  group('downgradeUnresolvedMentions', () {
    test('keeps a mention the check confirms', () {
      final text = _hiAlice('u1');

      expect(downgradeUnresolvedMentions(text, (id) => id == 'u1'), text);
    });

    test('turns one it does not confirm into the username it displays', () {
      expect(
        downgradeUnresolvedMentions(_hiAlice('u1'), (_) => false),
        RichText('hi @alice!', const [
          Entity(3, 6, EntityKind.username('alice')),
        ]),
      );
    });

    test('keeps the styles around the rewritten mention', () {
      final text = RichText('hi @alice!', const [
        Entity(0, 10, EntityKind.bold),
        Entity(3, 6, EntityKind.mention('u1')),
      ]);

      expect(
        downgradeUnresolvedMentions(text, (_) => false),
        RichText('hi @alice!', const [
          Entity(0, 10, EntityKind.bold),
          Entity(3, 6, EntityKind.username('alice')),
        ]),
      );
    });

    test('drops the entity, keeping the text, when it displays no @name', () {
      final text = RichText('hi Alice Smith!', const [
        Entity(3, 11, EntityKind.mention('u1')),
      ]);

      expect(
        downgradeUnresolvedMentions(text, (_) => false),
        const RichText.plain('hi Alice Smith!'),
      );
    });

    test('is the same value when there is nothing to rewrite', () {
      const plain = RichText.plain('no entities @here');
      final bold = RichText('bold', const [Entity(0, 4, EntityKind.bold)]);

      expect(
        identical(downgradeUnresolvedMentions(plain, (_) => false), plain),
        isTrue,
      );
      expect(
        identical(downgradeUnresolvedMentions(bold, (_) => false), bold),
        isTrue,
      );
    });
  });

  group('ComposerController.sendableText', () {
    late FakeRichClipboard clipboard;
    late ComposerController composer;

    setUp(() {
      clipboard = FakeRichClipboard();
      composer = ComposerController(
        clipboard: clipboard,
        queryKinds: [_mentionQuery],
      );
    });
    tearDown(() => composer.dispose());

    test('keeps a mention inserted by a query pick', () {
      composer.text.value = const TextEditingValue(
        text: 'hi @al',
        selection: TextSelection.collapsed(offset: 6),
      );
      final query = composer.query.value!;

      composer.replaceQuery(query, _hiAlice('u1').slice(3, 10));

      expect(composer.sendableText.entities.map((entity) => entity.kind), [
        const EntityKind.mention('u1'),
      ]);
    });

    test('keeps a mention restored for editing', () {
      composer.restore(_hiAlice('u1'));

      expect(composer.sendableText, _hiAlice('u1'));
    });

    test('keeps the mentions of a draft decoded from its stored markdown', () {
      // A restored draft is the host's own earlier state, whichever session
      // wrote it, so restore trusts its mentions: the ones to doubt are those
      // a paste brings in.
      final stored = RichTextMarkdown.encode(_hiAlice('u1'));

      composer.restore(RichTextMarkdown.decode(stored));

      expect(composer.sendableText, _hiAlice('u1'));
    });

    test('rewrites a mention pasted from foreign HTML', () async {
      await clipboard.write(_hiAlice('u1'));
      composer.restore(RichText.empty);

      await composer.paste();

      expect(composer.richText, _hiAlice('u1'));
      expect(
        composer.sendableText,
        RichText('hi @alice!', const [
          Entity(3, 6, EntityKind.username('alice')),
        ]),
      );
    });

    test(
      'keeps a pasted mention the host confirms against its users',
      () async {
        final confirming = ComposerController(
          clipboard: clipboard,
          confirmMention: (id) => id == 'u1',
        );
        addTearDown(confirming.dispose);
        await clipboard.write(_hiAlice('u1'));

        await confirming.paste();

        expect(confirming.sendableText, _hiAlice('u1'));
      },
    );

    test('keeps a mention the host marks resolved', () {
      composer.text.insert(_hiAlice('u1'));
      expect(
        composer.sendableText.entities.single.kind,
        isA<EntityKind$Username>(),
      );

      composer.trustMention('u1');

      expect(composer.sendableText, _hiAlice('u1'));
    });

    test('trust belongs to the draft: clear and restore forget it', () {
      composer.restore(_hiAlice('u1'));
      composer.clear();
      composer.text.insert(_hiAlice('u1'));
      expect(
        composer.sendableText.entities.single.kind,
        isA<EntityKind$Username>(),
      );

      composer.trustMention('u1');
      composer.restore(const RichText.plain('another draft'));
      composer.text.insert(_hiAlice('u1'));

      expect(
        composer.sendableText.entities.single.kind,
        isA<EntityKind$Username>(),
      );
    });

    test('leaves richText itself alone', () {
      composer.text.insert(_hiAlice('u1'));

      composer.sendableText;

      expect(composer.richText, _hiAlice('u1'));
    });
  });
}
