/// `EntityDetection` and `DetectionPolicy`: bare URLs, emails, `@name` and
/// `#tag` become entities with Telegram Android's rules.
///
/// **Seam:** `EntityDetection.apply` / `strip` over [RichText]. Case names
/// quote their source: the ticket's rule list, Android's `LinkifyPort` and
/// `MessageObject.urlPattern`, desktop's `MessageLinksParser`.
library;

import 'package:content_model/content_model.dart';
import 'package:test/test.dart';

const _all = DetectionPolicy();

/// The entities [EntityDetection.apply] adds to [text], each as
/// `(covered text, kind)`.
List<(String, EntityKind)> _found(
  String text, [
  DetectionPolicy policy = _all,
]) {
  final result = EntityDetection.apply(RichText.plain(text), policy);
  return [for (final e in result.entities) (result.textOf(e), e.kind)];
}

/// The URL targets found in [text], in order.
List<String> _links(String text, [DetectionPolicy policy = _all]) => [
  for (final (_, kind) in _found(text, policy))
    if (kind case EntityKind$Link(:final url)) url,
];

/// What [text] covers once as a single link, or null.
String? _linked(String text) {
  final found = _found(text);
  if (found.length != 1 || found.single.$2 is! EntityKind$Link) return null;
  return found.single.$1;
}

void main() {
  group('URL', () {
    test('https://a.b/c: a scheme accepts any host', () {
      expect(_found('https://a.b/c'), [
        ('https://a.b/c', const EntityKind.link('https://a.b/c')),
      ]);
    });

    test('a scheme is matched ignoring case and keeps its spelling', () {
      expect(_found('HTTP://A.B'), [
        ('HTTP://A.B', const EntityKind.link('HTTP://A.B')),
      ]);
    });

    test('a single-label host is fine behind a scheme', () {
      expect(_linked('http://localhost:8080/x'), 'http://localhost:8080/x');
    });

    test('a.com: a scheme-less host with a TLD from the list', () {
      expect(_found('a.com'), [
        ('a.com', const EntityKind.link('https://a.com')),
      ]);
    });

    test('www. is just a host', () {
      expect(_found('www.a.com'), [
        ('www.a.com', const EntityKind.link('https://www.a.com')),
      ]);
    });

    test('a.notatld: a scheme-less host without a TLD from the list', () {
      expect(_found('a.notatld'), isEmpty);
      expect(_found('file.txt'), isEmpty);
    });

    test('a single label is not a host without a scheme', () {
      expect(_found('com'), isEmpty);
      expect(_found('localhost'), isEmpty);
    });

    test('xn--p1ai.xn--p1ai: a punycode TLD is accepted by shape', () {
      expect(_linked('xn--p1ai.xn--p1ai'), 'xn--p1ai.xn--p1ai');
      expect(_links('xn--p1ai.xn--p1ai'), ['https://xn--p1ai.xn--p1ai']);
    });

    test('an IDN label before a TLD is a host', () {
      expect(_linked('пример.com/путь'), 'пример.com/путь');
    });

    test('a dotted IPv4 address is a host', () {
      expect(_links('go 192.168.0.1:8080/x'), ['https://192.168.0.1:8080/x']);
      expect(_found('1.2.3'), isEmpty);
      expect(_found('999.1.1.1'), isEmpty);
    });

    test('a TLD matches ignoring case', () {
      expect(_linked('Example.COM'), 'Example.COM');
    });

    test('a port and a query are part of the match', () {
      expect(_links('a.com:8080?q=1&r=a%20b#frag'), [
        'https://a.com:8080?q=1&r=a%20b#frag',
      ]);
    });

    test('a path with an at-sign and parentheses stays whole', () {
      expect(
        _linked('a.com/wiki/Dart_(language)'),
        'a.com/wiki/Dart_(language)',
      );
      expect(_linked('a.com/@user/x'), 'a.com/@user/x');
    });

    test('user info before the host belongs to a scheme URL', () {
      expect(_linked('https://user:pw@a.com/x'), 'https://user:pw@a.com/x');
    });

    test('a label over 63 characters is not a host', () {
      expect(_found('${'a' * 64}.com'), isEmpty);
      expect(_linked('${'a' * 63}.com'), '${'a' * 63}.com');
    });

    test('a host inside a longer word is not a match', () {
      expect(_found('fooa.b_c'), isEmpty);
      expect(_found('a.com_'), isEmpty);
    });

    group('trailing punctuation and brackets', () {
      test('(see a.com/x) keeps the brackets balanced', () {
        expect(_found('(see a.com/x)'), [
          ('a.com/x', const EntityKind.link('https://a.com/x')),
        ]);
        expect(_found('(a.com/x_(y))'), [
          ('a.com/x_(y)', const EntityKind.link('https://a.com/x_(y)')),
        ]);
      });

      test('a.com. and a.com, trim the punctuation', () {
        expect(_linked('a.com.'), 'a.com');
        expect(_linked('a.com,'), 'a.com');
        expect(_linked('a.com/x;'), 'a.com/x');
        expect(_linked('a.com/x!?'), 'a.com/x');
        expect(_linked('a.com/x:'), 'a.com/x');
        expect(_linked('"a.com/x"'), 'a.com/x');
        expect(_linked("'a.com/x'"), 'a.com/x');
      });

      test('a closing slash stays', () {
        expect(_linked('a.com/'), 'a.com/');
      });

      test('a sentence of two URLs splits at the comma', () {
        expect(_links('a.com, b.org.'), ['https://a.com', 'https://b.org']);
      });

      test('full-width punctuation and Latin-1 quotes end a URL', () {
        expect(_linked('见https://a.com/x，然后'), 'https://a.com/x');
        expect(_linked('«a.com/x»'), 'a.com/x');
      });
    });

    test('a match preceded by @ is rejected', () {
      expect(_found('@a.com'), [('@a', const EntityKind.username('a'))]);
      expect(_found('x@https://a.com'), isEmpty);
    });

    test('a scheme outside the policy set is not detected', () {
      expect(_found('ftp://a.com/x'), isEmpty);
      expect(_found('tg://resolve?domain=x'), isEmpty);
    });

    test('a scheme in the policy set is detected', () {
      const policy = DetectionPolicy(schemes: {'https', 'tg'});
      expect(_links('tg://resolve?domain=x', policy), [
        'tg://resolve?domain=x',
      ]);
      expect(_found('http://a.com', policy), isEmpty);
    });

    test('the implicit scheme is https when allowed, else the first', () {
      expect(_links('a.com', const DetectionPolicy(schemes: {'http'})), [
        'http://a.com',
      ]);
      expect(
        _links('a.com', const DetectionPolicy(schemes: {'http', 'https'})),
        ['https://a.com'],
      );
    });

    test('a scheme with nothing after it is not a match', () {
      expect(_found('https://'), isEmpty);
      expect(_found('see https:// now'), isEmpty);
    });
  });

  group('email', () {
    test('user@a.com is one mailto: link, not a URL after @', () {
      expect(_found('user@a.com'), [
        ('user@a.com', const EntityKind.link('mailto:user@a.com')),
      ]);
    });

    test('a dotted and tagged local part', () {
      expect(
        _linked('mail me: first.last+tag@sub.example.org.'),
        'first.last+tag@sub.example.org',
      );
    });

    test('the domain needs a TLD from the list', () {
      expect(_found('user@a.notatld'), isEmpty);
      expect(_found('user@localhost'), isEmpty);
    });

    test('a local part that starts with punctuation is not an email', () {
      expect(_found('-user@a.com'), isEmpty);
      expect(_found('.user@a.com'), isEmpty);
    });

    test('a local part over 64 characters is not an email', () {
      expect(_found('${'u' * 65}@a.com'), isEmpty);
      expect(_linked('${'u' * 64}@a.com'), '${'u' * 64}@a.com');
    });
  });

  group('username', () {
    test('@a after the start of the text', () {
      expect(_found('@a'), [('@a', const EntityKind.username('a'))]);
    });

    test('(@a_1 after a bracket', () {
      expect(_found('(@a_1'), [('@a_1', const EntityKind.username('a_1'))]);
    });

    test('after whitespace and a line break', () {
      expect(_found('hi @alice\n@bob!'), [
        ('@alice', const EntityKind.username('alice')),
        ('@bob', const EntityKind.username('bob')),
      ]);
    });

    test('a name stops at the first character outside [A-Za-z0-9_]', () {
      expect(_found('@ab-cd'), [('@ab', const EntityKind.username('ab'))]);
      expect(_found('@ab.cd'), [('@ab', const EntityKind.username('ab'))]);
    });

    test('32 characters match, 33 do not', () {
      expect(_found('@${'a' * 32}'), [
        ('@${'a' * 32}', EntityKind.username('a' * 32)),
      ]);
      expect(_found('@${'a' * 33}'), isEmpty);
    });

    test('x@a: not after whitespace, start or a bracket', () {
      expect(_found('x@a'), isEmpty);
      expect(_found('x@a.notatld'), isEmpty);
    });

    test('a bare @ is nothing', () {
      expect(_found('@'), isEmpty);
      expect(_found('@ a'), isEmpty);
      expect(_found('@!'), isEmpty);
    });
  });

  group('hashtag', () {
    test('#tag', () {
      expect(_found('#tag'), [('#tag', const EntityKind.hashtag('tag'))]);
    });

    test('#1tag: a digit may not follow the #', () {
      expect(_found('#1tag'), isEmpty);
      expect(_found('#123'), isEmpty);
    });

    test('#тег: Unicode letters', () {
      expect(_found('#тег'), [('#тег', const EntityKind.hashtag('тег'))]);
      expect(_found('go #日本語 now'), [
        ('#日本語', const EntityKind.hashtag('日本語')),
      ]);
    });

    test('digits, underscores and dots continue a tag', () {
      expect(_found('#a_1.b2'), [
        ('#a_1.b2', const EntityKind.hashtag('a_1.b2')),
      ]);
    });

    test('a sentence dot is not part of the tag', () {
      expect(_found('see #tag.'), [('#tag', const EntityKind.hashtag('tag'))]);
    });

    test('there is no @suffix form', () {
      expect(_found('#tag@bot'), [('#tag', const EntityKind.hashtag('tag'))]);
    });

    test('a tag needs a character after the first', () {
      expect(_found('#a'), isEmpty);
      expect(_found('#'), isEmpty);
      expect(_found('# tag'), isEmpty);
    });

    test('only after the start, whitespace or a bracket', () {
      expect(_found('(#tag'), [('#tag', const EntityKind.hashtag('tag'))]);
      expect(_found('a#tag'), isEmpty);
      expect(_found('a.com/#frag'), [
        ('a.com/#frag', const EntityKind.link('https://a.com/#frag')),
      ]);
    });
  });

  group('overlapping candidates', () {
    test('#a.com: the longest wins, a hashtag over the host inside it', () {
      expect(_found('#a.com'), [('#a.com', const EntityKind.hashtag('a.com'))]);
    });

    test('a URL with an at-sign path hides the username inside it', () {
      expect(_found('https://a.com/@user'), [
        ('https://a.com/@user', const EntityKind.link('https://a.com/@user')),
      ]);
    });

    test('unrelated matches all stay, in text order', () {
      expect(_found('#tt a.com @u'), [
        ('#tt', const EntityKind.hashtag('tt')),
        ('a.com', const EntityKind.link('https://a.com')),
        ('@u', const EntityKind.username('u')),
      ]);
    });
  });

  group('exclusions', () {
    RichText with_(String text, Entity entity) => RichText(text, [entity]);

    List<Entity> foundIn(RichText text) => EntityDetection.apply(text).entities;

    test('nothing inside inline code', () {
      const text = 'a.com @u #tag';
      final input = with_(text, const Entity(0, 13, EntityKind.code));
      expect(EntityDetection.apply(input), input);
    });

    test('nothing inside a code block', () {
      const text = 'a.com\n@u #tag';
      final input = with_(text, const Entity(0, 13, EntityKind.codeBlock()));
      expect(EntityDetection.apply(input), input);
    });

    test('nothing inside an existing link', () {
      const text = 'see a.com now';
      final input = with_(
        text,
        const Entity(4, 5, EntityKind.link('https://other.example')),
      );
      expect(EntityDetection.apply(input), input);
    });

    test('nothing inside a mention', () {
      const text = 'hi @alice.com!';
      final input = with_(text, const Entity(3, 10, EntityKind.mention('7')));
      expect(EntityDetection.apply(input), input);
    });

    test('nothing inside a username or a hashtag', () {
      final user = with_(
        'x a.com',
        const Entity(2, 5, EntityKind.username('a')),
      );
      expect(EntityDetection.apply(user), user);
      final tag = with_(
        'x #a.com',
        const Entity(2, 6, EntityKind.hashtag('a')),
      );
      expect(EntityDetection.apply(tag), tag);
    });

    test('nothing inside inline content', () {
      final input = with_(
        'see a.com',
        const Entity(4, 5, EntityKind.inlineContent(ContentKey.document('1'))),
      );
      expect(EntityDetection.apply(input), input);
    });

    test('a URL that crosses an atom is not detected', () {
      // The mention covers "com" of "a.com/x".
      final input = with_(
        'a.com/x',
        const Entity(2, 3, EntityKind.mention('7')),
      );
      expect(EntityDetection.apply(input), input);
      // The atom starts before the URL and ends inside it.
      final left = with_(
        'ab a.com',
        const Entity(0, 4, EntityKind.mention('7')),
      );
      expect(EntityDetection.apply(left), left);
    });

    test('a match next to an atom is detected', () {
      final input = with_(
        '@x a.com',
        const Entity(0, 2, EntityKind.mention('7')),
      );
      expect(foundIn(input).map((e) => e.kind), [
        const EntityKind.mention('7'),
        const EntityKind.link('https://a.com'),
      ]);
    });

    test('detection inside a spoiler works', () {
      final result = EntityDetection.apply(
        with_('see a.com', const Entity(0, 9, EntityKind.spoiler)),
      );
      expect(result.entities, const [
        Entity(0, 9, EntityKind.spoiler),
        Entity(4, 5, EntityKind.link('https://a.com')),
      ]);
    });

    test('styles do not block and keep their span', () {
      final result = EntityDetection.apply(
        with_('a.com now', const Entity(0, 9, EntityKind.bold)),
      );
      expect(result.entities, const [
        Entity(0, 9, EntityKind.bold),
        Entity(0, 5, EntityKind.link('https://a.com')),
      ]);
    });

    test('a quote and a list item do not block', () {
      final result = EntityDetection.apply(
        with_(
          '@u',
          const Entity(0, 2, EntityKind.list(listKind: EntityListKind.bullet)),
        ),
      );
      expect(result.entities, hasLength(2));
    });
  });

  group('policy', () {
    test('urls only detects no usernames or hashtags', () {
      const policy = DetectionPolicy.urlsOnly;
      expect(_found('@u #tag a.com', policy), [
        ('a.com', const EntityKind.link('https://a.com')),
      ]);
    });

    test('urls: false detects no URLs and no emails', () {
      const policy = DetectionPolicy(urls: false);
      expect(_found('a.com u@a.com @u #tag', policy), [
        ('@u', const EntityKind.username('u')),
        ('#tag', const EntityKind.hashtag('tag')),
      ]);
    });

    test('usernames: false and hashtags: false', () {
      expect(_found('@u #tag', const DetectionPolicy(usernames: false)), [
        ('#tag', const EntityKind.hashtag('tag')),
      ]);
      expect(_found('@u #tag', const DetectionPolicy(hashtags: false)), [
        ('@u', const EntityKind.username('u')),
      ]);
    });

    test('nothing enabled changes nothing', () {
      const text = 'a.com @u #tag';
      const input = RichText.plain(text);
      expect(
        EntityDetection.apply(
          input,
          const DetectionPolicy(urls: false, usernames: false, hashtags: false),
        ),
        same(input),
      );
    });

    test('compares by value', () {
      expect(const DetectionPolicy(), const DetectionPolicy());
      expect(
        const DetectionPolicy(schemes: {'http', 'https'}).hashCode,
        const DetectionPolicy().hashCode,
      );
      expect(const DetectionPolicy(), isNot(DetectionPolicy.urlsOnly));
      expect(
        const DetectionPolicy(),
        isNot(const DetectionPolicy(schemes: {'https'})),
      );
    });
  });

  group('caps', () {
    test('the 101st match is not produced', () {
      final text = List.generate(150, (i) => 'a$i.com').join(' ');
      final result = EntityDetection.apply(RichText.plain(text));
      expect(result.entities, hasLength(EntityDetection.maxMatches));
      expect(result.textOf(result.entities.last), 'a99.com');
    });

    test('matches of every kind share the cap', () {
      final text = List.generate(60, (i) => '@u$i #t$i').join(' ');
      expect(
        EntityDetection.apply(RichText.plain(text)).entities,
        hasLength(100),
      );
    });

    test('a text over 20 480 characters is returned unchanged', () {
      const tail = ' a.com';
      final over = 'x' * (EntityDetection.maxLength + 1 - tail.length) + tail;
      expect(over.length, 20481);
      final input = RichText.plain(over);
      expect(EntityDetection.apply(input), same(input));
    });

    test('a text of exactly 20 480 characters is scanned', () {
      const tail = ' a.com';
      final text = 'x' * (EntityDetection.maxLength - tail.length) + tail;
      expect(text.length, 20480);
      expect(
        EntityDetection.apply(RichText.plain(text)).entities,
        hasLength(1),
      );
    });
  });

  group('strip', () {
    test('strip(apply(x)) == x for a detected-only body', () {
      const bodies = [
        'see https://a.b/c and a.com, (b.org/x). mail u@a.com',
        '@alice and #tag and #тег. then www.a.com/x_(y)',
        'plain',
        '',
      ];
      for (final body in bodies) {
        final input = RichText.plain(body);
        expect(
          EntityDetection.strip(EntityDetection.apply(input)),
          input,
          reason: body,
        );
      }
    });

    test('strip keeps styles and other entities', () {
      final input = RichText('bold a.com', const [
        Entity(0, 4, EntityKind.bold),
        Entity(5, 5, EntityKind.underline),
      ]);
      expect(EntityDetection.strip(EntityDetection.apply(input)), input);
    });

    test('a user-made link with a label other than its URL survives', () {
      final input = RichText('click here', const [
        Entity(6, 4, EntityKind.link('https://a.com')),
      ]);
      expect(EntityDetection.strip(input), input);
    });

    test('a link labelled with its own URL is stripped', () {
      final input = RichText('https://a.com', const [
        Entity(0, 13, EntityKind.link('https://a.com')),
      ]);
      expect(
        EntityDetection.strip(input),
        const RichText.plain('https://a.com'),
      );
    });

    test('a link to another URL under a URL-looking label survives', () {
      final input = RichText('a.com', const [
        Entity(0, 5, EntityKind.link('https://evil.example')),
      ]);
      expect(EntityDetection.strip(input), input);
    });

    test('a mention is never stripped', () {
      final input = RichText('@alice', const [
        Entity(0, 6, EntityKind.mention('7')),
      ]);
      expect(EntityDetection.strip(input), input);
    });

    test('strip removes only what the policy would add back', () {
      final detected = EntityDetection.apply(
        const RichText.plain('a.com @u #tag'),
      );
      final stripped = EntityDetection.strip(
        detected,
        DetectionPolicy.urlsOnly,
      );
      expect(stripped.entities, const [
        Entity(6, 2, EntityKind.username('u')),
        Entity(9, 4, EntityKind.hashtag('tag')),
      ]);
    });

    test('a link labelled with a longer span than the URL survives', () {
      final input = RichText('see a.com now', const [
        Entity(0, 13, EntityKind.link('https://a.com')),
      ]);
      expect(EntityDetection.strip(input), input);
    });
  });

  group('idempotence', () {
    test('apply(apply(x)) == apply(x)', () {
      const bodies = [
        'see https://a.b/c, a.com. (b.org/x) u@a.com @alice #tag #1 #a.com',
        '`a.com` a.com',
        'x@a.com @a.com #a.com/x',
      ];
      for (final body in bodies) {
        final once = EntityDetection.apply(RichText.plain(body));
        expect(EntityDetection.apply(once), once, reason: body);
      }
    });

    test('also when the cap was hit', () {
      final text = List.generate(150, (i) => 'a$i.com').join(' ');
      final once = EntityDetection.apply(RichText.plain(text));
      expect(EntityDetection.apply(once), once);
    });

    test('a text with nothing to detect is returned as is', () {
      final input = RichText('plain', const [Entity(0, 5, EntityKind.bold)]);
      expect(EntityDetection.apply(input), same(input));
    });
  });

  group('budget', () {
    test('4096 code points are scanned well inside a frame', () {
      const unit = 'lorem ipsum https://a.b/c, dolor a.com @name #tag sit ';
      final text = (unit * 100).substring(0, 4096);
      final input = RichText.plain(text);
      EntityDetection.apply(input); // warm up
      final watch = Stopwatch()..start();
      const runs = 20;
      for (var i = 0; i < runs; i++) {
        EntityDetection.apply(input);
      }
      watch.stop();
      final perRun = watch.elapsedMicroseconds / runs;
      // Recorded, not a gate beyond "well inside a 16 ms frame".
      // ignore: avoid_print
      print(
        'EntityDetection.apply over 4096 code points: '
        '${perRun.toStringAsFixed(0)} us',
      );
      expect(perRun, lessThan(8000));
    });

    test('a pathological run of dotted labels stays linear', () {
      final text = 'a.' * 10000;
      final watch = Stopwatch()..start();
      EntityDetection.apply(RichText.plain(text));
      expect(watch.elapsedMilliseconds, lessThan(500));
    });
  });
}
