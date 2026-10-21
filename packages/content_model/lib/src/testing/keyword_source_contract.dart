import 'package:content_model/content_model.dart';
import 'package:test/test.dart';

/// A [KeywordSource] under test, with the languages the contract needs and
/// cannot invent.
final class KeywordSourceHarness {
  /// Creates a harness around [source].
  const KeywordSourceHarness({
    required this.source,
    required this.language,
    required this.unknownLanguage,
    this.publish,
  });

  /// The source under test, fresh.
  final KeywordSource source;

  /// A bare language tag (`en`, no region) the source has a pack for.
  final String language;

  /// A language tag, with no region, that the source has no pack for and
  /// whose primary subtag it has none for either.
  final String unknownLanguage;

  /// Makes the source receive [pack], as a server pack arriving would, and
  /// completes once it is answering with it. When null, the tests that need
  /// a pack to arrive are skipped.
  final Future<void> Function(KeywordPack pack)? publish;
}

/// The behaviour every [KeywordSource] must have, as a test suite to run
/// against an implementation.
abstract final class KeywordSourceContract {
  /// Runs the [KeywordSource] contract against the harnesses [create] returns,
  /// one per test.
  static void run(Future<KeywordSourceHarness> Function() create) {
    group('KeywordSource contract', () {
      late KeywordSourceHarness harness;
      late KeywordSource source;
      late int signals;

      setUp(() async {
        harness = await create();
        source = harness.source;
        signals = 0;
        source.changes.addListener(() => signals++);
      });

      tearDown(() => source.dispose());

      group('pack', () {
        test('answers with the pack of a language it has', () async {
          final pack = await source.pack(harness.language);

          expect(pack, isNotNull);
          expect(pack!.language, harness.language);
        });

        test('answers null for a language without keywords', () async {
          expect(await source.pack(harness.unknownLanguage), isNull);
        });

        test('falls back from a regional tag to its primary subtag', () async {
          final pack = await source.pack('${harness.language}-XX');

          expect(pack, isNotNull);
          expect(pack!.language, harness.language);
        });

        test(
          'answers null for a regional tag whose primary subtag is unknown',
          () async {
            expect(await source.pack('${harness.unknownLanguage}-XX'), isNull);
          },
        );

        test('does not signal by being read', () async {
          await source.pack(harness.language);
          await source.pack(harness.unknownLanguage);

          expect(signals, 0);
        });
      });

      group('a pack arriving', () {
        test('is answered for its language, and signalled once', () async {
          final publish = harness.publish;
          if (publish == null) {
            markTestSkipped('this source cannot be made to receive packs');
            return;
          }
          final arriving = KeywordPack(
            language: harness.unknownLanguage,
            version: 1,
            keywords: {
              const ContentKey.unicode('\u{1F44D}'): const ['thumbs up'],
            },
          );

          await publish(arriving);

          final pack = await source.pack(harness.unknownLanguage);
          expect(pack?.language, harness.unknownLanguage);
          expect(pack?.keywords, arriving.keywords);
          expect(signals, 1);
        });

        test(
          'is preferred to the primary subtag for its regional tag',
          () async {
            final publish = harness.publish;
            if (publish == null) {
              markTestSkipped('this source cannot be made to receive packs');
              return;
            }
            final regional = '${harness.language}-XX';
            await publish(
              KeywordPack(language: regional, version: 1, keywords: const {}),
            );

            expect((await source.pack(regional))?.language, regional);
            expect(
              (await source.pack(harness.language))?.language,
              harness.language,
            );
          },
        );
      });

      group('after dispose', () {
        test('is silent', () async {
          final publish = harness.publish;
          source.dispose();

          if (publish != null) {
            await publish(
              KeywordPack(
                language: harness.unknownLanguage,
                version: 1,
                keywords: const {},
              ),
            );
          }

          expect(signals, 0);
        });

        test('answers null', () async {
          source.dispose();

          expect(await source.pack(harness.language), isNull);
        });

        test('can be disposed twice', () {
          source.dispose();

          expect(source.dispose, returnsNormally);
        });
      });
    });
  }
}
