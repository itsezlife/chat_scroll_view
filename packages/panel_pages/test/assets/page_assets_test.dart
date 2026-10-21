import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/testing.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_pages/panel_pages.dart';

const _glyph = ContentKey.unicode('\u{1F44D}');
const _sticker = ContentKey.document('42');
const _spec = AssetSpec(pixelWidth: 72, pixelHeight: 72);
const _profile = AssetProfile();

void main() {
  late FakeAssetProducer producer;

  setUp(() => producer = FakeAssetProducer());

  AssetCacheScope scopeOf({GlyphSpriteSource? glyphSource}) {
    final scope = PageAssets.createScope(
      producer: producer,
      glyphSource: glyphSource,
      clock: PlaybackClock(ticks: ManualPlaybackTickSource()),
    );
    addTearDown(scope.dispose);
    return scope;
  }

  group('where nothing is baked', () {
    test('a unicode glyph is drawn as text and final at once', () {
      final binding = scopeOf().attach(_glyph, _spec, _profile);
      addTearDown(binding.detach);

      expect(
        binding.readiness,
        const AssetReadiness(AssetStage.full, isFinal: true),
      );
      expect(producer.attempts, isEmpty);
    });

    test('other content still goes to the producer', () {
      final binding = scopeOf().attach(_sticker, _spec, _profile);
      addTearDown(binding.detach);

      expect(producer.attempts, hasLength(1));
    });
  });

  group('where an atlas is registered', () {
    test(
      'a unicode glyph waits for its page and never reaches the text path',
      () {
        final source = FakeGlyphSpriteSource(['\u{1F44D}']);
        addTearDown(source.dispose);
        final binding = scopeOf(
          glyphSource: source,
        ).attach(_glyph, _spec, _profile);
        addTearDown(binding.detach);

        expect(binding.readiness.stage, AssetStage.placeholder);

        source.bakePage(0);

        expect(binding.readiness.stage, AssetStage.full);
        expect(binding.paintable.sprite, isNotNull);
      },
    );
  });
}
