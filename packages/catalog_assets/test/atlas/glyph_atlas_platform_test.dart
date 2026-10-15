import 'package:catalog_assets/glyph_atlas.dart';
import 'package:catalog_assets/src/atlas/platform/glyph_atlas_platform_baking.dart'
    as baking;
import 'package:catalog_assets/src/atlas/platform/glyph_atlas_platform_web.dart'
    as web;
import 'package:catalog_assets/testing.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// The platform choice is made once, by which strategy file the build picks
/// (`createGlyphAtlasForPlatform`): the two files are tested directly because a
/// VM test can only ever build the default one.
void main() {
  late FakeBakeFrameSource frames;
  late ValueNotifier<bool> visible;
  late ValueNotifier<bool> opening;

  setUp(() {
    frames = FakeBakeFrameSource();
    visible = ValueNotifier<bool>(true);
    opening = ValueNotifier<bool>(false);
  });
  tearDown(() {
    visible.dispose();
    opening.dispose();
  });

  GlyphAtlas? create(
    GlyphAtlas? Function({
      required GlyphAtlasIndex index,
      required GlyphRasteriser rasteriser,
      required GlyphPageStore store,
      required BakeFrameSource frames,
      required BakeClock clock,
      required ValueListenable<bool> panelVisible,
      required ValueListenable<bool> panelOpening,
    })
    factory,
  ) => factory(
    index: GlyphAtlasIndex(['a']),
    rasteriser: FakeGlyphRasteriser(),
    store: MemoryGlyphPageStore(),
    frames: frames,
    clock: ManualBakeClock().read,
    panelVisible: visible,
    panelOpening: opening,
  );

  test('a baking platform gets an atlas', () {
    final atlas = create(baking.createGlyphAtlasForPlatform);
    addTearDown(() => atlas?.dispose());

    expect(atlas, isNotNull);
  });

  test('the web gets none, so it bakes nothing and draws text', () {
    final atlas = create(web.createGlyphAtlasForPlatform);

    expect(atlas, isNull);
    expect(frames.requested, 0);
  });
}
