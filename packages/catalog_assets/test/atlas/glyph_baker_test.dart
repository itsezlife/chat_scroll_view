import 'dart:ui';

import 'package:catalog_assets/glyph_atlas.dart';
import 'package:catalog_assets/testing.dart';
import 'package:flutter_test/flutter_test.dart';

List<String> _glyphs(int count) => [for (var i = 0; i < count; i++) 'g$i'];

Future<void> _noFrameWait() async {}

void main() {
  late FakeGlyphRasteriser rasteriser;
  late FakeGlyphPageStore store;

  setUp(() {
    rasteriser = FakeGlyphRasteriser();
    store = FakeGlyphPageStore();
  });
  tearDown(() => store.clear());

  GlyphBaker bakerFor(List<String> glyphs) => GlyphBaker(
    index: GlyphAtlasIndex(glyphs),
    rasteriser: rasteriser,
    store: store,
  );

  /// Bakes everything and returns the baker; pages stay in [store].
  Future<GlyphBaker> bake(List<String> glyphs, {int perFrame = 16}) async {
    final baker = bakerFor(glyphs);
    addTearDown(baker.dispose);
    await baker.bakeAll(glyphsPerFrame: perFrame, nextFrame: _noFrameWait);
    return baker;
  }

  /// Asserts the sprite of every glyph points at that glyph's pixels.
  Future<void> expectSpritesHoldTheirGlyphs(
    GlyphBaker baker,
    List<String> glyphs,
  ) async {
    final pages = <int, ImagePixels>{};
    for (final glyph in glyphs) {
      final sprite = baker.spriteOf(glyph)!;
      final page = pages[sprite.pageIndex] ??= await ImagePixels.of(
        (await store.read(sprite.pageIndex))!,
      );
      // The centre of the sprite holds the glyph's predictable colour, and the
      // gutter around it is transparent.
      expect(
        page.at(
          sprite.source.center.dx.floor(),
          sprite.source.center.dy.floor(),
        ),
        FakeGlyphRasteriser.colorFor(glyph),
        reason: glyph,
      );
      expect(
        page.at(sprite.source.left.toInt() - 1, sprite.source.top.toInt() - 1),
        const Color(0x00000000),
        reason: '$glyph gutter',
      );
    }
  }

  test(
    'baking a small catalogue yields one page and a sprite per glyph',
    () async {
      final glyphs = _glyphs(40);
      final baker = await bake(glyphs);

      expect(baker.isComplete, isTrue);
      expect(await store.read(0), isNotNull);
      expect(await store.read(1), isNull);
      for (final glyph in glyphs) {
        expect(baker.spriteOf(glyph), baker.index.placementOf(glyph));
      }
      await expectSpritesHoldTheirGlyphs(baker, glyphs);
    },
  );

  test('a catalogue of exactly one page needs exactly one page', () async {
    const layout = GlyphAtlasLayout();
    final glyphs = _glyphs(layout.cellsPerPage);
    final baker = await bake(glyphs);

    expect(await store.read(0), isNotNull);
    expect(await store.read(1), isNull);
    await expectSpritesHoldTheirGlyphs(baker, glyphs);
  });

  test('a catalogue that needs more than one page bakes every page', () async {
    const layout = GlyphAtlasLayout();
    final glyphs = _glyphs(layout.cellsPerPage + 5);
    final baker = await bake(glyphs);

    expect(baker.index.pageCount, 2);
    expect(await store.read(1), isNotNull);
    expect(await store.read(2), isNull);
    await expectSpritesHoldTheirGlyphs(baker, glyphs);
  });

  test('stored pages are full 2048 px pages', () async {
    await bake(_glyphs(3));

    final page = (await store.read(0))!;
    expect(page.width, GlyphAtlasLayout.pageSize);
    expect(page.height, GlyphAtlasLayout.pageSize);
    page.dispose();
  });

  test('a glyph has no sprite until its page is composed', () async {
    const layout = GlyphAtlasLayout();
    final glyphs = _glyphs(layout.cellsPerPage + 1);
    final baker = bakerFor(glyphs);
    addTearDown(baker.dispose);

    expect(baker.spriteOf('g0'), isNull);
    // Strips of page 0 until it composes, one frame per step.
    BakeStep step;
    do {
      step = await baker.step(glyphs: 16);
    } while (step != BakeStep.page);

    expect(baker.spriteOf('g0'), isNotNull);
    expect(baker.spriteOf('g${layout.cellsPerPage}'), isNull);
    expect(baker.isComplete, isFalse);
  });

  test('every glyph is rasterised exactly once', () async {
    final glyphs = _glyphs(100);
    await bake(glyphs);

    expect(rasteriser.painted, glyphs);
  });

  test('a repeated glyph is rasterised once', () async {
    await bake(['a', 'b', 'a']);

    expect(rasteriser.painted, ['a', 'b']);
  });

  test(
    'a frame bakes at most the glyph budget and one page per frame',
    () async {
      final baker = bakerFor(_glyphs(32));
      addTearDown(baker.dispose);
      var frames = 0;

      await baker.bakeAll(glyphsPerFrame: 16, nextFrame: () async => frames++);

      // Two strips of 16 glyphs and one page composition.
      expect(frames, 3);
    },
  );

  test('a step budget smaller than the page paces the strips', () async {
    final baker = bakerFor(_glyphs(10));
    addTearDown(baker.dispose);

    expect(await baker.step(glyphs: 4), BakeStep.strip);
    expect(rasteriser.painted, hasLength(4));
    expect(await baker.step(glyphs: 4), BakeStep.strip);
    expect(await baker.step(glyphs: 4), BakeStep.strip);
    expect(rasteriser.painted, hasLength(10));
    expect(await baker.step(glyphs: 4), BakeStep.page);
    expect(await baker.step(glyphs: 4), BakeStep.done);
  });

  test('an empty catalogue is complete at once', () async {
    final baker = bakerFor(const []);
    addTearDown(baker.dispose);

    expect(baker.isComplete, isTrue);
    expect(await baker.step(glyphs: 16), BakeStep.done);
  });

  test('an unknown glyph has no sprite', () async {
    final baker = await bake(_glyphs(3));

    expect(baker.spriteOf('absent'), isNull);
  });
}
