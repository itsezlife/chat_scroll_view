/// A bake observer made of three functions, so a package that must not depend
/// on `catalog_assets` can still be shown the cells without a class of its own.
///
/// **Seam:** `GlyphBaker(observer:)`, the observer being a
/// `CallbackGlyphBakeObserver` over plain functions.
library;

import 'dart:typed_data';

import 'package:catalog_assets/glyph_atlas.dart';
import 'package:catalog_assets/testing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the baker draws the pending references and offers wanted cells '
      'through the functions', () async {
    final cells = <String, Uint8List>{};
    final references = ['REF'];
    final observer = CallbackGlyphBakeObserver(
      pendingReferences: () =>
          references.where((r) => !cells.containsKey(r)).toList(),
      wants: (glyph) => glyph != 'g1' && !cells.containsKey(glyph),
      observe: (glyph, rgba) => cells[glyph] = rgba,
    );
    final store = FakeGlyphPageStore();
    addTearDown(store.clear);
    final baker = GlyphBaker(
      index: GlyphAtlasIndex(['g0', 'g1', 'g2']),
      rasteriser: FakeGlyphRasteriser(),
      store: store,
      observer: observer,
    );
    addTearDown(baker.dispose);

    await baker.bakeAll(glyphsPerFrame: 16, nextFrame: () async {});
    await baker.observationsSettled();

    expect(cells.keys, unorderedEquals(['REF', 'g0', 'g2']));
  });
}
