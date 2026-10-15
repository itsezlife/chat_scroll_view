import 'package:catalog_assets/glyph_atlas.dart';
import 'package:catalog_assets/testing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  runBakeFrameSourceContract('FakeBakeFrameSource', (tester) {
    final source = FakeBakeFrameSource();
    return (source: source, nextFrame: () async => source.pump());
  });
  runBakeFrameSourceContract('SchedulerBakeFrameSource', (tester) {
    final source = SchedulerBakeFrameSource(view: tester.view);
    addTearDown(source.dispose);
    return (source: source, nextFrame: tester.pump);
  });
  runGlyphRasteriserContract('FakeGlyphRasteriser', FakeGlyphRasteriser.new);
  runGlyphRasteriserContract(
    'ParagraphGlyphRasteriser',
    ParagraphGlyphRasteriser.new,
    glyphs: const ['A', '😀', '👨‍👩‍👧‍👦', '🇯🇵'],
  );
  runGlyphPageStoreContract('FakeGlyphPageStore', FakeGlyphPageStore.new);
  runGlyphPageStoreContract('MemoryGlyphPageStore', MemoryGlyphPageStore.new);
}
