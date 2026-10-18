/// The draft contract: a draft is the markdown string the wire carries, and
/// `richText` and `restore` are its two ends, lossless for every kind.
///
/// **Seam:** [ComposerController.richText] and [ComposerController.restore]
/// around `RichTextMarkdown`, the pair a host's draft store wraps.
library;

import 'package:chat_composer/chat_composer.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/markdown.dart';
import 'package:content_model/testing.dart';
import 'package:flutter/widgets.dart' hide RichText;
import 'package:flutter_test/flutter_test.dart';

/// [plain] with [kind] over each of [parts], found in order.
RichText _text(String plain, List<(String, EntityKind)> parts) {
  var from = 0;
  return RichText(plain, [
    for (final (part, kind) in parts)
      () {
        from = plain.indexOf(part, from);
        final entity = Entity(from, part.length, kind);
        from += part.length;
        return entity;
      }(),
  ]);
}

final _corpus = <String, RichText>{
  'plain': const RichText.plain('just text'),
  'styles': _text('bold italic under strike spoiler code', [
    ('bold', EntityKind.bold),
    ('italic', EntityKind.italic),
    ('under', EntityKind.underline),
    ('strike', EntityKind.strike),
    ('spoiler', EntityKind.spoiler),
    ('code', EntityKind.code),
  ]),
  'overlapping styles': RichText('both styles here', const [
    Entity(0, 11, EntityKind.bold),
    Entity(5, 11, EntityKind.italic),
  ]),
  'link': _text('see the docs now', [
    ('the docs', const EntityKind.link('https://example.com/a?b=1')),
  ]),
  'mention and detected names': _text('hi @alice and @bob #dart', [
    ('@alice', const EntityKind.mention('u1')),
    ('@bob', const EntityKind.username('bob')),
    ('#dart', const EntityKind.hashtag('dart')),
  ]),
  'inline content': _text('ok \u{1F44D} and \u{1F680}', [
    ('\u{1F44D}', const EntityKind.inlineContent(ContentKey.unicode('1F44D'))),
    ('\u{1F680}', const EntityKind.inlineContent(ContentKey.document('5368'))),
  ]),
  'quote': _text('before\nquoted line\nafter', [
    ('quoted line', EntityKind.quote),
  ]),
  'code block': _text('run:\nprint(1);\nend', [
    ('print(1);', const EntityKind.codeBlock(language: 'dart')),
  ]),
  'lists': _text('intro\none\ntwo\nnested\nthree', [
    ('one', const EntityKind.list(listKind: EntityListKind.ordered)),
    ('two', const EntityKind.list(listKind: EntityListKind.ordered)),
    (
      'nested',
      const EntityKind.list(listKind: EntityListKind.bullet, depth: 1),
    ),
    ('three', const EntityKind.list(listKind: EntityListKind.ordered)),
  ]),
  'markdown-looking text': const RichText.plain(
    '2 * 3 = 6, [not a link](x), # not a heading, a_b_c, ~~, ||',
  ),
  'emoji, newlines and a trailing space': const RichText.plain(
    '\u{1F44D}\n\n\u{1F44D} ',
  ),
};

void main() {
  late ComposerController composer;

  setUp(() => composer = ComposerController());
  tearDown(() => composer.dispose());

  for (final MapEntry(:key, :value) in _corpus.entries) {
    test('restore(decode(encode(richText))) keeps $key', () {
      composer.restore(value);
      final before = composer.richText;

      composer.restore(
        RichTextMarkdown.decode(RichTextMarkdown.encode(composer.richText)),
      );

      expect(before, value);
      expect(composer.richText, before);
    });
  }

  test('a draft of emoji and blank lines keeps its newlines and trailing '
      'space', () {
    composer.text.value = const TextEditingValue(
      text: '\u{1F44D}\n\n\u{1F44D} ',
      selection: TextSelection.collapsed(offset: 7),
    );

    expect(composer.richText.plain, '\u{1F44D}\n\n\u{1F44D} ');
    expect(composer.sendableText.plain, '\u{1F44D}\n\n\u{1F44D} ');
  });

  test('a host stores the draft as its markdown and loads it back', () async {
    // The pattern the README documents: written under a key of the chat id,
    // read when the chat opens.
    final store = FakeKeyValueStore();
    composer.restore(_corpus['lists']!);
    await store.write(
      'drafts',
      'chat-7',
      StoredValue(RichTextMarkdown.encode(composer.richText), version: 1),
    );

    final reopened = ComposerController();
    addTearDown(reopened.dispose);
    final stored = await store.read('drafts', 'chat-7');
    reopened.restore(RichTextMarkdown.decode(stored!.value));

    expect(reopened.richText, _corpus['lists']);
  });
}
