import 'package:catalog_assets/catalog_assets.dart';
import 'package:flutter_test/flutter_test.dart';

/// A scope whose unicode glyphs are drawn as text, the strategy of a platform
/// that bakes nothing, and whose other content never arrives.
///
/// Disposed when the test ends. Tests that need a baking platform build their
/// scope with a `glyphSource`; tests of content that loads build it with a
/// `FakeAssetProducer`.
AssetCacheScope textGlyphScope({AssetProducer? next}) {
  final scope = AssetCacheScope(producer: TextGlyphProducer(next: next));
  addTearDown(scope.dispose);
  return scope;
}
