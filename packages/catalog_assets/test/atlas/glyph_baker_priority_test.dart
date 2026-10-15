import 'package:catalog_assets/glyph_atlas.dart';
import 'package:catalog_assets/testing.dart';
import 'package:flutter_test/flutter_test.dart';

const _perPage = 676; // GlyphAtlasLayout().cellsPerPage

List<String> _glyphs(int count) => [for (var i = 0; i < count; i++) 'g$i'];

void main() {
  late FakeGlyphRasteriser rasteriser;
  late FakeGlyphPageStore store;

  setUp(() {
    rasteriser = FakeGlyphRasteriser();
    store = FakeGlyphPageStore();
  });
  tearDown(() => store.clear());

  // Three pages: 0..675, 676..1351, 1352..1361.
  GlyphBaker threePageBaker() {
    final baker = GlyphBaker(
      index: GlyphAtlasIndex(_glyphs(2 * _perPage + 10)),
      rasteriser: rasteriser,
      store: store,
    );
    addTearDown(baker.dispose);
    return baker;
  }

  /// Steps until a page is composed; returns the page index.
  Future<int> stepToNextPage(GlyphBaker baker, {int glyphs = 16}) async {
    BakeStep step;
    do {
      step = await baker.step(glyphs: glyphs);
    } while (step == BakeStep.strip);
    expect(step, BakeStep.page);
    return baker.lastBakedPage!;
  }

  test('without a priority pages bake in catalogue order', () async {
    final baker = threePageBaker();

    expect(await stepToNextPage(baker), 0);
    expect(await stepToNextPage(baker), 1);
    expect(await stepToNextPage(baker), 2);
    expect(baker.isComplete, isTrue);
  });

  test('the page holding the visible glyphs bakes first', () async {
    final baker = threePageBaker()..prioritise(['g${_perPage + 3}']);

    expect(await stepToNextPage(baker), 1);
    expect(baker.spriteOf('g${_perPage + 3}'), isNotNull);
    expect(baker.spriteOf('g0'), isNull);
  });

  test('after the visible page the nearest pages follow', () async {
    final baker = threePageBaker()..prioritise(['g${2 * _perPage + 1}']);

    expect(await stepToNextPage(baker), 2);
    expect(await stepToNextPage(baker), 1);
    expect(await stepToNextPage(baker), 0);
  });

  test('a band across a page boundary bakes both of its pages first', () async {
    final baker = threePageBaker()
      ..prioritise(['g${_perPage - 1}', 'g$_perPage']);

    expect(await stepToNextPage(baker), 0);
    expect(await stepToNextPage(baker), 1);
  });

  test(
    'a new priority leaves the page in progress for the visible one',
    () async {
      final baker = threePageBaker();
      // Page 0 half done.
      for (var i = 0; i < 20; i++) {
        expect(await baker.step(glyphs: 16), BakeStep.strip);
      }

      baker.prioritise(['g${2 * _perPage + 1}']);

      expect(await stepToNextPage(baker), 2);
      expect(baker.isPageBaked(0), isFalse);
      // The abandoned page bakes again, from scratch, and everything completes.
      while (!baker.isComplete) {
        await baker.step(glyphs: 16);
      }
      for (var i = 0; i < baker.index.glyphCount; i++) {
        expect(baker.spriteOf('g$i'), baker.index.placementOf('g$i'));
      }
    },
  );

  test('a priority inside the page in progress does not restart it', () async {
    final baker = threePageBaker();
    for (var i = 0; i < 20; i++) {
      await baker.step(glyphs: 16);
    }

    baker.prioritise(['g3']);
    await stepToNextPage(baker);

    expect(rasteriser.painted.where((g) => g == 'g0'), hasLength(1));
  });

  test('clearing the priority returns to catalogue order', () async {
    final baker = threePageBaker()
      ..prioritise(['g${2 * _perPage + 1}'])
      ..prioritise(const []);

    expect(await stepToNextPage(baker), 0);
  });

  test('glyphs outside the catalogue are ignored', () async {
    final baker = threePageBaker()..prioritise(['absent']);

    expect(await stepToNextPage(baker), 0);
  });

  test('priority never moves a glyph to another cell', () async {
    final prioritised = threePageBaker()..prioritise(['g${_perPage + 3}']);
    while (!prioritised.isComplete) {
      await prioritised.step(glyphs: 16);
    }

    for (var i = 0; i < prioritised.index.glyphCount; i++) {
      expect(
        prioritised.spriteOf('g$i'),
        prioritised.index.placementOf('g$i'),
        reason: 'g$i',
      );
    }
  });
}
