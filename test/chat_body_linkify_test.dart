import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const webUrls = ChatLinkifyPolicy.webUrls;

  group('ChatBodyLinkify web URLs', () {
    test('rewrites bare https URL into a markdown link', () {
      expect(
        ChatBodyLinkify.apply(
          'see https://example.com/path for docs',
          policy: webUrls,
        ),
        'see [https://example.com/path](https://example.com/path) for docs',
      );
    });

    test('rewrites bare http URL into a markdown link', () {
      expect(
        ChatBodyLinkify.apply('open http://example.com now', policy: webUrls),
        'open [http://example.com](http://example.com) now',
      );
    });

    test('rewrites www URL with https target', () {
      expect(
        ChatBodyLinkify.apply('visit www.example.com/docs', policy: webUrls),
        'visit [www.example.com/docs](https://www.example.com/docs)',
      );
    });

    test('does not rewrite inside a fenced code block', () {
      const input = '''
before
```
https://example.com
```
after''';
      expect(ChatBodyLinkify.apply(input, policy: webUrls), input);
    });

    test('does not rewrite inside inline code', () {
      const input = 'use `https://example.com` in the snippet';
      expect(ChatBodyLinkify.apply(input, policy: webUrls), input);
    });

    test('does not rewrite an existing markdown link', () {
      const input = 'go to [docs](https://example.com/docs) please';
      expect(ChatBodyLinkify.apply(input, policy: webUrls), input);
    });

    test('leaves non-allowlisted schemes plain', () {
      const input = 'magnet:?xt=urn:btih:abc ftp://files.example.com';
      expect(ChatBodyLinkify.apply(input, policy: webUrls), input);
    });

    test('is idempotent for web URLs', () {
      const input = 'see https://example.com and www.example.org';
      final once = ChatBodyLinkify.apply(input, policy: webUrls);
      expect(ChatBodyLinkify.apply(once, policy: webUrls), once);
    });

    test('leaves trailing sentence punctuation outside the link', () {
      expect(
        ChatBodyLinkify.apply('See https://example.com.', policy: webUrls),
        'See [https://example.com](https://example.com).',
      );
    });

    test('rewrites free text while preserving excluded regions', () {
      const input =
          'https://free.example '
          '`https://code.example` '
          '[keep](https://kept.example) '
          'www.also.example';
      expect(
        ChatBodyLinkify.apply(input, policy: webUrls),
        '[https://free.example](https://free.example) '
        '`https://code.example` '
        '[keep](https://kept.example) '
        '[www.also.example](https://www.also.example)',
      );
    });

    test('webUrls flag does not rewrite mentions', () {
      expect(ChatBodyLinkify.apply('hi @alice', policy: webUrls), 'hi @alice');
    });
  });

  group('ChatBodyLinkify mentions', () {
    test('rewrites @username into a mention-scheme markdown link', () {
      expect(ChatBodyLinkify.apply('hi @alice'), 'hi [@alice](mention:alice)');
    });

    test('rewrites mentions and web URLs in one pass', () {
      expect(
        ChatBodyLinkify.apply('ping @bob at https://example.com'),
        'ping [@bob](mention:bob) at '
        '[https://example.com](https://example.com)',
      );
    });

    test('does not rewrite mentions inside fenced code', () {
      const input = '''
before
```
@alice
```
after''';
      expect(ChatBodyLinkify.apply(input), input);
    });

    test('does not rewrite mentions inside inline code', () {
      const input = 'use `@alice` in the snippet';
      expect(ChatBodyLinkify.apply(input), input);
    });

    test('does not rewrite an existing mention markdown link', () {
      const input = 'go to [@alice](mention:alice) please';
      expect(ChatBodyLinkify.apply(input), input);
    });

    test('does not treat email local-parts as mentions', () {
      const input = 'mail user@example.com please';
      expect(ChatBodyLinkify.apply(input), input);
    });

    test('leaves @ inside a schemed URL to the URL rewrite', () {
      expect(
        ChatBodyLinkify.apply('see https://example.com/@alice'),
        'see [https://example.com/@alice](https://example.com/@alice)',
      );
    });

    test('is idempotent for mentions and mixed tokens', () {
      const input = 'hi @alice see https://example.com';
      final once = ChatBodyLinkify.apply(input);
      expect(ChatBodyLinkify.apply(once), once);
    });
  });

  group('ChatLinkifyPolicy bitmask', () {
    test('mentions-only rewrites mentions and leaves URLs plain', () {
      expect(
        ChatBodyLinkify.apply(
          'hi @alice see https://example.com',
          policy: ChatLinkifyPolicy.mentions,
        ),
        'hi [@alice](mention:alice) see https://example.com',
      );
    });

    test('webUrls.add(mentions) equals webAndMentions', () {
      final combined = ChatLinkifyPolicy.webUrls.add(
        ChatLinkifyPolicy.mentions,
      );
      expect(combined, ChatLinkifyPolicy.webAndMentions);
      expect(
        ChatBodyLinkify.apply(
          'hi @alice see https://example.com',
          policy: combined,
        ),
        ChatBodyLinkify.apply('hi @alice see https://example.com'),
      );
    });

    test('add and remove compose allowlists', () {
      final withMentions = ChatLinkifyPolicy.webUrls.add(
        ChatLinkifyPolicy.mentions,
      );
      expect(withMentions, ChatLinkifyPolicy.webAndMentions);
      expect(
        withMentions.remove(ChatLinkifyPolicy.mentions),
        ChatLinkifyPolicy.webUrls,
      );
    });

    test('none leaves text unchanged', () {
      const input = 'hi @alice see https://example.com';
      expect(
        ChatBodyLinkify.apply(input, policy: ChatLinkifyPolicy.none),
        input,
      );
    });
  });
}
