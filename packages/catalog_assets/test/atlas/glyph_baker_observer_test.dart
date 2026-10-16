/// The bake pass shared with a pixel observer (the glyph-support probe): every
/// glyph is rasterised once, and the observer is shown the cell it drew.
///
/// **Seam:** `GlyphBaker(observer:)` with a `FakeGlyphRasteriser` (which
/// records every glyph it is asked to paint) and a `FakeGlyphBakeObserver`.
library;

import 'dart:ui';

import 'package:catalog_assets/glyph_atlas.dart';
import 'package:catalog_assets/testing.dart';
import 'package:flutter/foundation.dart';
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

  GlyphBaker bakerFor(List<String> glyphs, GlyphBakeObserver? observer) {
    final baker = GlyphBaker(
      index: GlyphAtlasIndex(glyphs),
      rasteriser: rasteriser,
      store: store,
      observer: observer,
    );
    addTearDown(baker.dispose);
    return baker;
  }

  Future<GlyphBaker> bake(
    List<String> glyphs,
    GlyphBakeObserver? observer,
  ) async {
    final baker = bakerFor(glyphs, observer);
    await baker.bakeAll(glyphsPerFrame: 16, nextFrame: _noFrameWait);
    await baker.observationsSettled();
    return baker;
  }

  /// The colour at the middle of an observed cell.
  Color centre(Uint8List rgba, int cell) {
    final i = ((cell ~/ 2) * cell + cell ~/ 2) * 4;
    return Color.fromARGB(rgba[i + 3], rgba[i], rgba[i + 1], rgba[i + 2]);
  }

  test('the observer is shown the cell each glyph was drawn to', () async {
    final glyphs = _glyphs(40);
    final observer = FakeGlyphBakeObserver();

    final baker = await bake(glyphs, observer);

    final cell = baker.index.layout.cellSize;
    expect(observer.cells.keys, unorderedEquals(glyphs));
    for (final glyph in glyphs) {
      final rgba = observer.cells[glyph]!;
      expect(rgba.length, cell * cell * 4, reason: glyph);
      expect(centre(rgba, cell), FakeGlyphRasteriser.colorFor(glyph));
      // The gutter corner of the cell is transparent.
      expect(rgba.sublist(0, 4), [0, 0, 0, 0], reason: '$glyph gutter');
    }
  });

  test(
    'no glyph is rasterised twice when the bake feeds the observer',
    () async {
      final glyphs = _glyphs(40);

      await bake(glyphs, FakeGlyphBakeObserver(references: const ['REF']));

      expect(rasteriser.painted.toSet(), hasLength(rasteriser.painted.length));
      expect(rasteriser.painted.where(glyphs.contains), hasLength(40));
    },
  );

  test(
    'a reference is drawn once, only for the observer, never baked',
    () async {
      final observer = FakeGlyphBakeObserver(references: const ['REF']);

      final baker = await bake(_glyphs(3), observer);

      expect(rasteriser.painted.where((g) => g == 'REF'), hasLength(1));
      expect(observer.cells.keys, contains('REF'));
      expect(baker.index.placementOf('REF'), isNull);
      expect(observer.pendingReferences, isEmpty);
    },
  );

  test('references the observer already has are not drawn', () async {
    final observer = FakeGlyphBakeObserver(); // none pending

    await bake(_glyphs(3), observer);

    expect(rasteriser.painted, isNot(contains('REF')));
    expect(rasteriser.painted, hasLength(3));
  });

  test('a glyph the observer does not want is baked but not offered', () async {
    final observer = FakeGlyphBakeObserver(known: const ['g1']);

    final baker = await bake(_glyphs(3), observer);

    expect(observer.offers, isNot(contains('g1')));
    expect(observer.offers, containsAll(['g0', 'g2']));
    expect(baker.spriteOf('g1'), isNotNull);
  });

  test('a strip nobody wants costs no readback', () async {
    final observer = FakeGlyphBakeObserver(known: _glyphs(40));

    await bake(_glyphs(40), observer);

    expect(observer.offers, isEmpty);
  });

  test('pages are identical with and without an observer', () async {
    final glyphs = _glyphs(40);
    final unobserved = FakeGlyphPageStore();
    addTearDown(unobserved.clear);
    final plain = GlyphBaker(
      index: GlyphAtlasIndex(glyphs),
      rasteriser: FakeGlyphRasteriser(),
      store: unobserved,
    );
    addTearDown(plain.dispose);
    await plain.bakeAll(glyphsPerFrame: 16, nextFrame: _noFrameWait);

    final observed = await bake(
      glyphs,
      FakeGlyphBakeObserver(references: const ['REF']),
    );

    final expected = await ImagePixels.of((await unobserved.read(0))!);
    final actual = await ImagePixels.of((await store.read(0))!);
    for (final glyph in glyphs) {
      final spot = observed.index.placementOf(glyph)!.source.center;
      expect(
        actual.at(spot.dx.floor(), spot.dy.floor()),
        expected.at(spot.dx.floor(), spot.dy.floor()),
        reason: glyph,
      );
    }
  });

  test(
    'an observer that throws is reported and the bake still finishes',
    () async {
      final errors = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = errors.add;
      addTearDown(() => FlutterError.onError = previous);
      final observer = FakeGlyphBakeObserver(failOn: 'g1');

      final baker = await bake(_glyphs(3), observer);

      expect(baker.isComplete, isTrue);
      expect(errors, isNotEmpty);
      expect(errors.first.exception, isStateError);
    },
  );

  test('after dispose a late readback is dropped', () async {
    final observer = FakeGlyphBakeObserver();
    final baker = bakerFor(_glyphs(3), observer);

    await baker.step(glyphs: 16);
    baker.dispose();
    await baker.observationsSettled();

    expect(observer.offers, isEmpty);
  });
}
