import 'dart:typed_data';

import 'package:catalog_assets/glyph_atlas.dart';
import 'package:emoji_data/emoji_data.dart';

/// Lets the bake pass of the glyph atlas feed a [MissingGlyphProbe]: the cells
/// the baker draws anyway become the probe's evidence, so no glyph is
/// rasterised a second time to find out whether the system can draw it.
///
/// The two packages do not know each other (the data layer must not depend on
/// the asset layer, nor the reverse), and both speak plain bytes, so the host
/// joins them here.
final class GlyphProbeBakeObserver implements GlyphBakeObserver {
  /// Creates an observer feeding [probe].
  const GlyphProbeBakeObserver(this.probe);

  /// The probe fed.
  final MissingGlyphProbe probe;

  @override
  List<String> get pendingReferences => probe.pendingReferences;

  @override
  bool wants(String glyph) => probe.wants(glyph);

  @override
  void observe(String glyph, Uint8List rgba) => probe.observe(glyph, rgba);
}
