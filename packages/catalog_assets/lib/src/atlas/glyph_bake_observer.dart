import 'dart:typed_data';

/// Somebody who wants to look at the pixels the bake rasterises anyway, so it
/// need not rasterise the glyphs a second time. The glyph-support probe is the
/// reason: it compares each glyph's cell with a missing-glyph reference.
///
/// The baker offers each glyph's cell once, right after the glyph is drawn
/// into a strip, and only for glyphs the observer [wants]; a glyph nobody
/// wants costs no readback. Cells are the full baked cell (glyph plus its
/// transparent gutter), RGBA8888, `cellSize * cellSize * 4` bytes, all the same
/// size, so equal pixels compare equal across glyphs.
///
/// Observation is off the baking path: it runs after the strip is made, a
/// strip at a time, never delays a [GlyphBaker.step], and an observer that
/// throws is reported and loses only its own data. It is pure Dart (bytes in),
/// so a package that must not depend on this one can implement it with a
/// three-line adapter; `catalog_assets` itself depends on no probe.
///
/// [GlyphBaker.step]: package:catalog_assets/glyph_atlas.dart
abstract interface class GlyphBakeObserver {
  /// Glyphs the observer wants drawn once, before the plan, only as
  /// comparison cells (a missing-glyph reference). They are drawn in a strip
  /// of their own that is never baked into a page, and only while this is not
  /// empty. Empty once the observer has them.
  List<String> get pendingReferences;

  /// Whether the observer still needs the cell of [glyph]. Asked before each
  /// readback, so a glyph already known (restored from a persisted result) is
  /// not read back.
  bool wants(String glyph);

  /// The cell [glyph] was drawn to. Called once per wanted glyph and per
  /// reference, in no promised order, possibly after later strips were made.
  void observe(String glyph, Uint8List rgba);
}
