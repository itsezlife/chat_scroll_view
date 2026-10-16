/// One glyph source over several: the first is the background bake, the
/// ones added after it bake on demand.
///
/// **Seam:** [LayeredGlyphSource] over [FakeGlyphSpriteSource] layers,
/// observed through what it answers and what its listeners hear.
library;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/testing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeGlyphSpriteSource base;
  late FakeGlyphSpriteSource extra;
  late LayeredGlyphSource layered;

  setUp(() {
    base = FakeGlyphSpriteSource(['a', 'b']);
    extra = FakeGlyphSpriteSource(['x', 'y']);
    layered = LayeredGlyphSource(base);
    addTearDown(() {
      layered.dispose();
      base.dispose();
      extra.dispose();
    });
  });

  runGlyphSpriteSourceContract(() {
    final source = FakeGlyphSpriteSource(['a']);
    final layers = LayeredGlyphSource(source);
    addTearDown(() {
      layers.dispose();
      source.dispose();
    });
    return GlyphSpriteSourceHarness(
      source: layers,
      plannedGlyph: 'a',
      unplannedGlyph: 'z',
      bake: () async => source.bakePage(0),
      holdsOnPageOfPlannedGlyph: () => source.holdCount(0),
    );
  });

  test('answers each glyph from the layer that has it', () {
    layered.add(extra);
    base.bakePage(0);
    extra.bakePage(0);

    expect(layered.spriteOf('a'), isNotNull);
    expect(layered.spriteOf('x'), isNotNull);
    expect(layered.spriteOf('z'), isNull);
  });

  test('a page index names one page image across every layer: a surface '
      'that batches by it draws each glyph from its own page', () {
    // Both layers number their pages from 0.
    layered.add(extra);
    base.bakePage(0);
    extra.bakePage(0);

    final a = layered.spriteOf('a')!;
    final x = layered.spriteOf('x')!;

    expect(a.page, isNot(same(x.page)));
    expect(a.pageIndex, isNot(x.pageIndex));
    expect(layered.spriteOf('b')!.pageIndex, a.pageIndex);
  });

  test('a page listener hears the index its sprites carry', () {
    final heard = <int>[];
    layered
      ..add(extra)
      ..addPageListener(heard.add);

    extra.bakePage(0);

    expect(heard, contains(layered.spriteOf('x')!.pageIndex));
  });

  test('a hold is taken on the layer that has the glyph', () {
    layered.add(extra);

    final hold = layered.holdPageOf('y')!;
    expect(extra.holdCount(0), 1);
    expect(base.holdCount(0), 0);

    hold.release();
    expect(extra.holdCount(0), 0);
    expect(layered.holdPageOf('z'), isNull);
  });

  test('only the first layer makes a surface wait: the others bake on '
      'demand', () {
    layered.add(extra);

    expect(layered.waitsForSprite('a'), isTrue);
    expect(layered.waitsForSprite('x'), isFalse);
    expect(layered.waitsForSprite('z'), isFalse);
  });

  test('listeners hear every layer, one added later too, and not a layer '
      'that was removed', () {
    final heard = <int>[];
    layered.addPageListener(heard.add);

    layered.add(extra);
    extra.bakePage(0);
    expect(heard, isNotEmpty, reason: 'a layer added later');

    layered.remove(extra);
    heard.clear();
    extra.bakePage(0);
    expect(heard, isEmpty, reason: 'a removed layer');

    base.bakePage(0);
    expect(heard, isNotEmpty);
  });

  test('adding a layer is a change surfaces hear: their glyphs may be '
      'drawable now', () {
    final heard = <int>[];
    layered.addPageListener(heard.add);

    layered.add(extra);

    expect(heard, isNotEmpty);
  });

  test('is inert after dispose', () {
    final heard = <int>[];
    layered
      ..addPageListener(heard.add)
      ..dispose();

    base.bakePage(0);
    expect(heard, isEmpty);
    expect(layered.spriteOf('a'), isNull);
  });
}
