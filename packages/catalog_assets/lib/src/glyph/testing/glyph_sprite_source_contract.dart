import 'package:catalog_assets/src/glyph/glyph_sprite_source.dart';
import 'package:flutter_test/flutter_test.dart';

/// What a [GlyphSpriteSource] contract run needs besides the source.
final class GlyphSpriteSourceHarness {
  /// Creates a harness around [source].
  const GlyphSpriteSourceHarness({
    required this.source,
    required this.plannedGlyph,
    required this.unplannedGlyph,
    required this.bake,
    required this.holdsOnPageOfPlannedGlyph,
  });

  /// The source under test.
  final GlyphSpriteSource source;

  /// A glyph the source knows.
  final String plannedGlyph;

  /// A glyph the source does not know.
  final String unplannedGlyph;

  /// Makes the page of [plannedGlyph] drawable and lets listeners hear it.
  final Future<void> Function() bake;

  /// How many holds cover the page of [plannedGlyph] right now. Only
  /// differences are asserted, so a source with a baseline hold (an open
  /// panel) is fine.
  final int Function() holdsOnPageOfPlannedGlyph;
}

/// The contract every [GlyphSpriteSource] meets; see its documentation.
abstract final class GlyphSpriteSourceContract {
  /// Runs it as a test group. [create] builds a fresh harness for each test.
  static void run(GlyphSpriteSourceHarness Function() create) {
    group('GlyphSpriteSource contract', () {
      late GlyphSpriteSourceHarness harness;

      setUp(() => harness = create());

      test(
        'has no sprite and no page to hold for an unplanned glyph',
        () async {
          await harness.bake();

          expect(harness.source.spriteOf(harness.unplannedGlyph), isNull);
          expect(harness.source.holdPageOf(harness.unplannedGlyph), isNull);
        },
      );

      test(
        'has no sprite for a planned glyph until its page is baked',
        () async {
          expect(harness.source.spriteOf(harness.plannedGlyph), isNull);

          await harness.bake();

          final sprite = harness.source.spriteOf(harness.plannedGlyph);
          expect(sprite, isNotNull);
          expect(sprite!.pageIndex, isNonNegative);
        },
      );

      test('makes a surface wait for a planned glyph and not for an unplanned '
          'one', () {
        expect(harness.source.waitsForSprite(harness.plannedGlyph), isTrue);
        expect(harness.source.waitsForSprite(harness.unplannedGlyph), isFalse);
      });

      test('tells page listeners when a page becomes drawable', () async {
        final heard = <int>[];
        harness.source.addPageListener(heard.add);

        await harness.bake();

        expect(heard, isNotEmpty);
      });

      test('tells a removed listener nothing', () async {
        final heard = <int>[];
        harness.source
          ..addPageListener(heard.add)
          ..removePageListener(heard.add);

        await harness.bake();

        expect(heard, isEmpty);
      });

      test('a hold covers the page until released, once', () {
        final before = harness.holdsOnPageOfPlannedGlyph();

        final first = harness.source.holdPageOf(harness.plannedGlyph)!;
        final second = harness.source.holdPageOf(harness.plannedGlyph)!;
        expect(harness.holdsOnPageOfPlannedGlyph(), before + 2);

        first.release();
        expect(first.isReleased, isTrue);
        expect(harness.holdsOnPageOfPlannedGlyph(), before + 1);

        first.release();
        expect(
          harness.holdsOnPageOfPlannedGlyph(),
          before + 1,
          reason: 'a second release takes nothing from the other claim',
        );

        second.release();
        expect(harness.holdsOnPageOfPlannedGlyph(), before);
      });
    });
  }
}
