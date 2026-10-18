import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:flutter_test/flutter_test.dart';

/// `inlineHitAt` is the pure model query behind every inline hit: which kind
/// of hit a span is, read from its style bits and not from its URL.
void main() {
  late ChatSelectionController selection;

  setUp(() => selection = ChatSelectionController());
  tearDown(() => selection.dispose());

  ChatInlineHit? hitAt(String source, int offset) {
    selection.putBody(1, Markdown.fromString(source));
    return selection.inlineHitAt(messageId: 1, blockIndex: 0, offset: offset);
  }

  group('an image span', () {
    test('is an embed with its target and alt, not a link', () {
      final hit = hitAt('hi ![:wave:](unicode:1F44B) there', 4);

      expect(
        hit,
        const ChatInlineHit.embed(
          messageId: 1,
          target: 'unicode:1F44B',
          alt: ':wave:',
        ),
      );
    });

    test('is an embed whatever its scheme', () {
      final hit = hitAt('![sticker](document:5368)', 2);

      expect(hit, isA<ChatInlineHit$Embed>());
      expect((hit! as ChatInlineHit$Embed).target, 'document:5368');
    });

    test('is never a link', () {
      for (final source in [
        '![a](unicode:1F44B)',
        '![a](https://a.b/c.png)',
        '![a](mention:1)',
      ]) {
        expect(
          hitAt(source, 0),
          isNot(isA<ChatInlineHit$Link>()),
          reason: source,
        );
      }
    });
  });

  group('a mention-class span', () {
    test('a resolved mention carries its id and label', () {
      final hit = hitAt('see [@Ann](mention:42) now', 6);

      expect(
        hit,
        const ChatInlineHit.mention(
          messageId: 1,
          kind: ChatMentionKind.resolved,
          id: '42',
          name: '@Ann',
        ),
      );
    });

    test('a username carries its name and no id', () {
      final hit = hitAt('see [@ann](username:ann) now', 6);

      expect(
        hit,
        const ChatInlineHit.mention(
          messageId: 1,
          kind: ChatMentionKind.username,
          name: 'ann',
        ),
      );
    });

    test('a hashtag carries its tag', () {
      final hit = hitAt('go [#tag](hashtag:tag) now', 4);

      expect(hit, const ChatInlineHit.hashtag(messageId: 1, tag: 'tag'));
    });

    test('is not a link', () {
      for (final source in [
        '[@a](mention:1)',
        '[@a](username:a)',
        '[#t](hashtag:t)',
      ]) {
        expect(
          hitAt(source, 1),
          isNot(isA<ChatInlineHit$Link>()),
          reason: source,
        );
      }
    });
  });

  group('everything else', () {
    test('a plain link is still a link', () {
      final hit = hitAt('a [site](https://a.b) b', 3);

      expect(
        hit,
        const ChatInlineHit.link(
          messageId: 1,
          title: 'site',
          url: 'https://a.b',
        ),
      );
    });

    test('inline code is still code', () {
      expect(hitAt('a `x` b', 2), isA<ChatInlineHit$Code>());
    });

    test('plain text is no hit', () {
      expect(hitAt('just words', 3), isNull);
    });
  });

  group('inside a hidden spoiler', () {
    const source = 'x ||[site](https://a.b)|| y';

    test('a link is no hit while the message is hidden', () {
      expect(hitAt(source, 3), isNull);
    });

    test('a mention, an embed and a hashtag are no hit either', () {
      for (final source in [
        '||[@a](mention:1)||',
        '||![a](unicode:1F44B)||',
        '||[#t](hashtag:t)||',
        '||`code`||',
      ]) {
        expect(hitAt(source, 0), isNull, reason: source);
      }
    });

    test('the same hit appears once the message is revealed', () {
      selection.spoilers.reveal(1);

      expect(hitAt(source, 3), isA<ChatInlineHit$Link>());
    });

    test('revealing one message leaves another hidden', () {
      selection.spoilers.reveal(2);

      expect(hitAt(source, 3), isNull);
    });

    test('a link outside the spoiler is a hit while the spoiler is hidden', () {
      expect(hitAt('||x|| [site](https://a.b)', 6), isA<ChatInlineHit$Link>());
    });
  });
}
