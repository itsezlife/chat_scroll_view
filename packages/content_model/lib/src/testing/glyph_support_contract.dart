import 'package:content_model/content_model.dart';
import 'package:test/test.dart';

/// A [GlyphSupport] under test, with the means to make it learn.
final class GlyphSupportHarness {
  /// Creates a harness around [support].
  const GlyphSupportHarness({required this.support, required this.learn});

  /// The source under test, fresh: it has learned nothing.
  final GlyphSupport support;

  /// Makes the source establish, in one step, that the [missing] keys are not
  /// drawn and/or that the emoji art is now [artVersion]; completes once the
  /// source is answering accordingly.
  final Future<void> Function({
    Set<ContentKey$Unicode> missing,
    String? artVersion,
  })
  learn;
}

/// The behaviour every [GlyphSupport] must have, as a test suite to run against
/// an implementation.
abstract final class GlyphSupportContract {
  /// Runs the [GlyphSupport] contract against the harnesses [create] returns,
  /// one per test.
  static void run(Future<GlyphSupportHarness> Function() create) {
    group('GlyphSupport contract', () {
      const thumbs = ContentKey$Unicode('\u{1F44D}');
      const heart = ContentKey$Unicode('\u{2764}\u{FE0F}');
      const flag = ContentKey$Unicode('\u{1F3F4}\u{200D}\u{2620}\u{FE0F}');

      late GlyphSupportHarness harness;
      late GlyphSupport support;
      late int signals;

      setUp(() async {
        harness = await create();
        support = harness.support;
        signals = 0;
        support.changes.addListener(() => signals++);
      });

      tearDown(() => support.dispose());

      test('supports every key until it learns otherwise', () {
        expect(support.supports(thumbs), isTrue);
        expect(support.supports(heart), isTrue);
        expect(support.supports(flag), isTrue);
      });

      test('has no art version until it knows it', () {
        expect(support.artVersion, isNull);
      });

      test(
        'stops supporting a key it learns is missing, and only that key',
        () async {
          await harness.learn(missing: {flag});

          expect(support.supports(flag), isFalse);
          expect(support.supports(thumbs), isTrue);
          expect(support.supports(heart), isTrue);
        },
      );

      test('signals once for a step, however many keys it covered', () async {
        await harness.learn(missing: {flag, heart});

        expect(support.supports(flag), isFalse);
        expect(support.supports(heart), isFalse);
        expect(signals, 1);
      });

      test('reports the art version it learns', () async {
        await harness.learn(artVersion: 'v1');

        expect(support.artVersion, 'v1');
        expect(signals, 1);
      });

      test(
        'signals once for a new art version with its answers together',
        () async {
          await harness.learn(missing: {flag}, artVersion: 'v1');

          expect(support.artVersion, 'v1');
          expect(support.supports(flag), isFalse);
          expect(signals, 1);
        },
      );

      test('is not signalled by being read', () {
        support
          ..supports(thumbs)
          ..artVersion;

        expect(signals, 0);
      });

      group('after dispose', () {
        test('is silent', () async {
          support.dispose();

          await harness.learn(missing: {flag});

          expect(signals, 0);
        });

        test('keeps the last answers readable', () async {
          await harness.learn(missing: {flag}, artVersion: 'v1');

          support.dispose();

          expect(support.supports(flag), isFalse);
          expect(support.supports(thumbs), isTrue);
          expect(support.artVersion, 'v1');
        });

        test('can be disposed twice', () {
          support.dispose();

          expect(support.dispose, returnsNormally);
        });
      });
    });
  }
}
