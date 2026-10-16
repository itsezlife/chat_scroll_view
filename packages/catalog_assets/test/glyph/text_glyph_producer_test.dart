import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/testing.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _glyph = ContentKey.unicode('\u{1F44D}');
const _sticker = ContentKey.document('42');
final _preset = AssetPresets.keyboardCell(extent: 20, devicePixelRatio: 2);

void main() {
  late FakeAssetProducer next;

  setUp(() => next = FakeAssetProducer());

  AssetCacheScope scopeOf(
    TextGlyphProducer producer, {
    AssetCacheBudgets budgets = AssetCacheBudgets.defaults,
  }) {
    final scope = AssetCacheScope(
      producer: producer,
      budgets: budgets,
      clock: PlaybackClock(ticks: ManualPlaybackTickSource()),
    );
    addTearDown(scope.dispose);
    return scope;
  }

  group('unicode glyphs', () {
    test('are final at once, without waiting for anything', () {
      final scope = scopeOf(TextGlyphProducer(next: next));

      final binding = scope.attach(_glyph, _preset.spec, _preset.profile);
      addTearDown(binding.detach);

      expect(
        binding.readiness,
        const AssetReadiness(AssetStage.full, isFinal: true),
      );
      expect(next.attempts, isEmpty);
    });

    test('have no sprite and do not animate', () {
      final scope = scopeOf(const TextGlyphProducer());

      final binding = scope.attach(_glyph, _preset.spec, _preset.profile);
      addTearDown(binding.detach);

      expect(binding.paintable.sprite, isNull);
      expect(binding.paintable.isAnimated, isFalse);
    });

    test('paint as one paragraph into the rectangle', () {
      final scope = scopeOf(const TextGlyphProducer());
      final binding = scope.attach(_glyph, _preset.spec, _preset.profile);
      addTearDown(binding.detach);
      final canvas = TestRecordingCanvas();

      binding.paint(canvas, const Rect.fromLTWH(0, 0, 20, 20));

      expect(_drawn(canvas), ['drawParagraph']);
    });

    test('paint again at another size', () {
      final scope = scopeOf(const TextGlyphProducer());
      final binding = scope.attach(_glyph, _preset.spec, _preset.profile);
      addTearDown(binding.detach);
      final canvas = TestRecordingCanvas();

      binding.paint(canvas, const Rect.fromLTWH(0, 0, 20, 20));
      binding.paint(canvas, const Rect.fromLTWH(0, 0, 40, 40));
      binding.paint(canvas, const Rect.fromLTWH(0, 0, 40, 40));

      expect(_drawn(canvas), everyElement('drawParagraph'));
      expect(_drawn(canvas), hasLength(3));
    });

    test('fade as a whole when the opacity is below one', () {
      final scope = scopeOf(const TextGlyphProducer());
      final binding = scope.attach(_glyph, _preset.spec, _preset.profile);
      addTearDown(binding.detach);
      final canvas = TestRecordingCanvas();

      binding.paint(canvas, const Rect.fromLTWH(0, 0, 20, 20), opacity: 0.5);

      expect(
        _drawn(canvas),
        containsAllInOrder(['saveLayer', 'drawParagraph']),
      );
    });

    test('are bounded by the cache budget like any entry', () {
      final scope = scopeOf(
        const TextGlyphProducer(paragraphBytes: 1000),
        budgets: const AssetCacheBudgets(stillBytes: 2500, animatedBytes: 0),
      );

      for (var i = 0; i < 5; i++) {
        scope
            .attach(
              ContentKey.unicode(String.fromCharCode(0x1F600 + i)),
              _preset.spec,
              _preset.profile,
            )
            .detach();
      }

      expect(scope.bytesIn(AssetTier.still), 2000);
      expect(scope.entryCount, 2);
    });
  });

  group('other content', () {
    test('goes to the producer it wraps', () {
      final scope = scopeOf(TextGlyphProducer(next: next));

      final binding = scope.attach(_sticker, _preset.spec, _preset.profile);
      addTearDown(binding.detach);

      expect(next.attempts.single.request.key, _sticker);
    });

    test('stays at none when there is nothing to wrap', () {
      final scope = scopeOf(const TextGlyphProducer());

      final binding = scope.attach(_sticker, _preset.spec, _preset.profile);
      addTearDown(binding.detach);

      expect(binding.readiness.stage, AssetStage.none);
    });

    test('cancels with the wrapped producer', () {
      final scope = scopeOf(TextGlyphProducer(next: next));

      scope.attach(_sticker, _preset.spec, _preset.profile).detach();

      expect(next.attempts.single.isCancelled, isTrue);
    });
  });

  testWidgets('a ContentView with no atlas paints the glyph as text', (
    tester,
  ) async {
    final scope = scopeOf(TextGlyphProducer(next: next));
    final still = AssetPresets.keyboardCell(
      extent: 20,
      devicePixelRatio: 2,
      animate: false,
    );

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: ContentView(content: _glyph, preset: still, scope: scope),
        ),
      ),
    );

    final canvas = TestRecordingCanvas();
    tester
        .renderObject<RenderBox>(find.byType(ContentView))
        .paint(TestRecordingPaintingContext(canvas), Offset.zero);
    expect(_drawn(canvas), ['drawParagraph']);
  });
}

List<String> _drawn(TestRecordingCanvas canvas) => [
  for (final call in canvas.invocations)
    call.invocation.memberName.toString().replaceAll(
      RegExp(r'Symbol\("|"\)'),
      '',
    ),
].where((name) => name.startsWith('draw') || name == 'saveLayer').toList();
