import 'package:catalog_assets/glyph_atlas.dart';
import 'package:panel_pages/src/bake/bake_activity_port.dart';

/// A [BakeActivityPort] over a [GlyphAtlas]: the two calls a page makes, one
/// to one.
///
/// A port per atlas: when the host plans a new atlas it gives the page a new
/// port, and the page's forwarder hands it the current motion and band.
final class GlyphAtlasBakePort implements BakeActivityPort {
  /// A port that reports to [atlas].
  const GlyphAtlasBakePort(this.atlas);

  /// The atlas the page's activity reaches.
  final GlyphAtlas atlas;

  @override
  void reportScrolling({required Object reporter, required bool scrolling}) =>
      atlas.reportScrolling(reporter: reporter, scrolling: scrolling);

  @override
  void prioritise(List<String> glyphs) => atlas.prioritise(glyphs);
}
