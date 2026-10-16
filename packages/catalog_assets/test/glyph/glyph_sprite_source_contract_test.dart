import 'package:catalog_assets/glyph_atlas.dart';
import 'package:catalog_assets/testing.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FakeGlyphSpriteSource', () {
    GlyphSpriteSourceContract.run(() {
      final fake = FakeGlyphSpriteSource(['a', 'b', 'c']);
      addTearDown(fake.dispose);
      return GlyphSpriteSourceHarness(
        source: fake,
        plannedGlyph: 'b',
        unplannedGlyph: 'z',
        bake: () async => fake.bakePage(0),
        holdsOnPageOfPlannedGlyph: () => fake.holdCount(0),
      );
    });
  });

  group('GlyphAtlas', () {
    GlyphSpriteSourceContract.run(() {
      final frames = FakeBakeFrameSource();
      final visible = ValueNotifier<bool>(true);
      final opening = ValueNotifier<bool>(false);
      final atlas = GlyphAtlas(
        index: GlyphAtlasIndex(['a', 'b']),
        rasteriser: FakeGlyphRasteriser(),
        store: FakeGlyphPageStore(),
        frames: frames,
        clock: ManualBakeClock().read,
        panelVisible: visible,
        panelOpening: opening,
        residency: GlyphPageResidency(
          startTimer: ManualRetentionTimers().start,
        ),
      )..start();
      addTearDown(() {
        atlas.dispose();
        visible.dispose();
        opening.dispose();
      });
      return GlyphSpriteSourceHarness(
        source: atlas,
        plannedGlyph: 'b',
        unplannedGlyph: 'z',
        bake: () async {
          while (frames.hasPendingRequest) {
            frames.pump();
            await pumpEventQueue();
          }
        },
        holdsOnPageOfPlannedGlyph: () => atlas.residency.holdCount(0),
      );
    });
  });
}
