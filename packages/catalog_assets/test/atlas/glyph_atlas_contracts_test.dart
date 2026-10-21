import 'package:catalog_assets/glyph_atlas.dart';
import 'package:catalog_assets/testing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  BakeFrameSourceContract.run('FakeBakeFrameSource', (tester) {
    final source = FakeBakeFrameSource();
    return (source: source, nextFrame: () async => source.pump());
  });
  BakeFrameSourceContract.run('SchedulerBakeFrameSource', (tester) {
    final source = SchedulerBakeFrameSource(view: tester.view);
    addTearDown(source.dispose);
    return (source: source, nextFrame: tester.pump);
  });
  GlyphRasteriserContract.run('FakeGlyphRasteriser', FakeGlyphRasteriser.new);
  // The test font draws each code point as its own square, so a family or a
  // flag is not a glyph it can form (it is drawn as nothing; see
  // paragraph_glyph_rasteriser_test.dart).
  GlyphRasteriserContract.run(
    'ParagraphGlyphRasteriser',
    ParagraphGlyphRasteriser.new,
    glyphs: const ['A', '😀'],
  );
  GlyphPageStoreContract.run('FakeGlyphPageStore', FakeGlyphPageStore.new);
  GlyphPageStoreContract.run('MemoryGlyphPageStore', MemoryGlyphPageStore.new);
  GlyphCacheStoreContract.run(
    'MemoryGlyphCacheStore',
    MemoryGlyphCacheStore.new,
  );
  GlyphCacheStoreContract.run('FakeGlyphCacheStore', FakeGlyphCacheStore.new);
}
