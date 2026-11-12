/// Which pack a tap in the chat names, and the packs of a message's custom
/// emoji.
///
/// **Seam:** [ChatPackTargets] over a describe function standing for the
/// host's descriptors.
library;

import 'package:chat_scroll_view_example/src/features/chat/utils/chat_pack_targets.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter_test/flutter_test.dart';

const _cats = PackId('cats');
const _dogs = PackId('dogs');
const _stickers = PackId('stickers');

final Map<ContentKey, ContentDescriptor> _known = {
  for (final (id, kind, pack) in [
    ('cat1', SemanticKind.customEmoji, _cats),
    ('cat2', SemanticKind.customEmoji, _cats),
    ('dog1', SemanticKind.customEmoji, _dogs),
    ('sticker1', SemanticKind.sticker, _stickers),
  ])
    ContentKey.document(id): ContentDescriptor(
      key: ContentKey.document(id),
      semanticKind: kind,
      pack: pack,
    ),
  const ContentKey.document('loose'): const ContentDescriptor(
    key: ContentKey.document('loose'),
    semanticKind: SemanticKind.customEmoji,
  ),
};

ContentDescriptor? _describe(ContentKey key) => _known[key];

String _emoji(String id) => '![x](document:$id)';

void main() {
  group('a tap names', () {
    test('the pack of a lone document', () {
      expect(
        ChatPackTargets.ofContent(
          const ContentKey.document('sticker1'),
          _describe,
        ),
        _stickers,
      );
    });

    test('no pack for a unicode emoji, or content of none', () {
      expect(
        ChatPackTargets.ofContent(const ContentKey.unicode('👍'), _describe),
        isNull,
      );
      expect(
        ChatPackTargets.ofContent(
          const ContentKey.document('loose'),
          _describe,
        ),
        isNull,
      );
    });

    test(
      'the pack of an embed by its target, none for a target not content',
      () {
        expect(ChatPackTargets.ofEmbed('document:dog1', _describe), _dogs);
        expect(ChatPackTargets.ofEmbed('sticker:42', _describe), isNull);
      },
    );
  });

  group('the emoji packs of a message', () {
    test('are each pack once, in the order the text first names them', () {
      expect(
        ChatPackTargets.emojiPacksOf(
          'a ${_emoji('dog1')} b ${_emoji('cat1')}${_emoji('cat2')} '
          '${_emoji('dog1')}',
          _describe,
        ),
        [_dogs, _cats],
      );
    });

    test('leave out stickers, emoji of no pack and unknown documents', () {
      expect(
        ChatPackTargets.emojiPacksOf(
          '${_emoji('sticker1')} ${_emoji('loose')} ${_emoji('missing')} 👍',
          _describe,
        ),
        isEmpty,
      );
    });
  });
}
