import 'package:catalog_assets/glyph_atlas.dart';
import 'package:catalog_assets/src/atlas/environment_specific/glyph_atlas_js.dart'
    as js;
import 'package:catalog_assets/src/atlas/environment_specific/glyph_atlas_vm.dart'
    as vm;
import 'package:catalog_assets/testing.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// The platform choice is made once, by which strategy file the build picks
/// ([GlyphAtlas.forPlatform]): the two files are tested directly because a
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
    GlyphAtlas? Function(GlyphAtlasRequest request) factory, {
    GlyphPageResidency? residency,
  }) => factory(
    GlyphAtlasRequest(
      index: GlyphAtlasIndex(['a']),
      rasteriser: FakeGlyphRasteriser(),
      store: MemoryGlyphPageStore(),
      frames: frames,
      clock: ManualBakeClock().read,
      panelVisible: visible,
      panelOpening: opening,
      residency: residency,
    ),
  );

  test('a baking platform gets an atlas', () {
    final atlas = create(vm.$createGlyphAtlas);
    addTearDown(() => atlas?.dispose());

    expect(atlas, isNotNull);
  });

  test('a baking platform hands the residency to its atlas', () {
    final residency = GlyphPageResidency();
    final atlas = create(vm.$createGlyphAtlas, residency: residency);
    addTearDown(() => atlas?.dispose());

    expect(atlas!.residency, same(residency));
  });

  test('the web gets none, so it bakes nothing and draws text', () {
    final atlas = create(js.$createGlyphAtlas);

    expect(atlas, isNull);
    expect(frames.requested, 0);
  });
}
