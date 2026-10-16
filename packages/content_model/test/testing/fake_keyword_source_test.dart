import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:test/test.dart';

const _thumbs = ContentKey.unicode('\u{1F44D}');

KeywordPack _pack(String language, {int version = 1}) => KeywordPack(
  language: language,
  version: version,
  keywords: {
    _thumbs: [language],
  },
);

void main() {
  KeywordSourceContract.run(() async {
    final source = FakeKeywordSource([_pack('en'), _pack('de')]);
    return KeywordSourceHarness(
      source: source,
      language: 'en',
      unknownLanguage: 'ja',
      publish: (pack) async => source.publish(pack),
    );
  });

  group('FakeKeywordSource', () {
    test('replaces the pack of a language with a newer one', () async {
      final source = FakeKeywordSource([_pack('en')])
        ..publish(_pack('en', version: 2));

      expect((await source.pack('en'))?.version, 2);
    });

    test(
      'fails to read an existing pack on request, not a missing one',
      () async {
        final source = FakeKeywordSource([_pack('en')])
          ..failure = Exception('unreadable');

        await expectLater(source.pack('en'), throwsException);
        expect(await source.pack('ja'), isNull);
      },
    );
  });
}
