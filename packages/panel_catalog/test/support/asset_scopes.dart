import 'package:content_assets/content_assets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpx_core/mpx_core.dart';

/// A scope whose unicode glyphs are drawn as text, the strategy of a platform
/// that bakes nothing, and whose other content never arrives.
///
/// Disposed when the test ends. Tests that need a baking platform build their
/// scope with a `glyphSource`; tests of content that loads build it with a
/// `FakeAssetProducer`.
ContentAssetScope textGlyphScope({AssetProducer? next}) {
  final scope = ContentAssetScope.withMedia(producer: next);
  addTearDown(scope.dispose);
  return scope;
}
