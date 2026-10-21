import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:emoji_data/emoji_data.dart';
import 'package:test/test.dart';

ContentKey$Unicode _key(String hex) =>
    ContentKey.parse('unicode:$hex') as ContentKey$Unicode;

KeywordPack _pack(
  String language,
  Map<String, List<String>> keywords, {
  int version = 0,
}) => KeywordPack(
  language: language,
  version: version,
  keywords: {for (final e in keywords.entries) _key(e.key): e.value},
);

void main() {
  late FakeKeywordSource base;
  late FakeKeywordSource overlay;
  late LayeredKeywordSource layered;

  setUp(() {
    base = FakeKeywordSource([
      _pack('en', {
        '1F600': ['grinning face', 'happy'],
        '1F44D': ['thumbs up'],
      }),
    ]);
    overlay = FakeKeywordSource();
    layered = LayeredKeywordSource(base: base, overlay: overlay);
  });

  tearDown(() {
    layered.dispose();
    base.dispose();
    overlay.dispose();
  });

  KeywordSourceContract.run(() async {
    final base = FakeKeywordSource([
      _pack('en', {
        '1F600': ['grinning face'],
      }),
    ]);
    final overlay = FakeKeywordSource();
    return KeywordSourceHarness(
      source: LayeredKeywordSource(base: base, overlay: overlay),
      language: 'en',
      unknownLanguage: 'xx',
      publish: (pack) async => overlay.publish(pack),
    );
  });

  group('pack', () {
    test('is the base pack while the overlay has none', () async {
      expect(await layered.pack('en'), same(await base.pack('en')));
    });

    test('is the overlay pack when the base has none', () async {
      final arriving = _pack('de', {
        '1F600': ['grinsen'],
      }, version: 7);
      overlay.publish(arriving);

      expect(await layered.pack('de'), same(arriving));
    });

    test(
      'lets the overlay replace the keywords of a key and add keys',
      () async {
        overlay.publish(
          _pack('en', {
            '1F600': ['smirk'],
            '1FAE8': ['shaking face'],
          }, version: 3),
        );

        final merged = (await layered.pack('en'))!;

        expect(merged.language, 'en');
        expect(merged.version, 3);
        expect(merged.keywords, {
          _key('1F600'): ['smirk'],
          _key('1F44D'): ['thumbs up'],
          _key('1FAE8'): ['shaking face'],
        });
      },
    );

    test(
      'answers the same merged pack until one of the inputs changes',
      () async {
        overlay.publish(
          _pack('en', {
            '1F600': ['smirk'],
          }),
        );
        final first = await layered.pack('en');

        expect(await layered.pack('en'), same(first));

        overlay.publish(
          _pack('en', {
            '1F600': ['frown'],
          }),
        );

        expect(await layered.pack('en'), isNot(same(first)));
      },
    );
  });

  group('changes', () {
    test('signal when the overlay or the base receives a pack', () async {
      var signals = 0;
      layered.changes.addListener(() => signals++);

      overlay.publish(_pack('de', {}));
      base.publish(_pack('fr', {}));

      expect(signals, 2);
    });

    test('stop after dispose, and leave the inputs usable', () async {
      var signals = 0;
      layered.changes.addListener(() => signals++);

      layered.dispose();
      overlay.publish(_pack('de', {}));

      expect(signals, 0);
      expect(await base.pack('en'), isNotNull);
    });
  });
}
