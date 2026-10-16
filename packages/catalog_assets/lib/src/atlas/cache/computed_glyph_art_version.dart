import 'package:catalog_assets/src/atlas/cache/glyph_art_version_source.dart';

/// A [GlyphArtVersionSource] whose answer is worked out once, by the host's
/// own code, and then remembered: the pixel fingerprint of a few sentinel
/// glyphs (`computeGlyphArtFingerprint` in `emoji_data`) is the intended
/// [compute].
///
/// "Once" matters: [GlyphAtlas] may read the version again, and a fingerprint
/// costs a render per sentinel. The first [read] starts [compute]; later and
/// concurrent reads share that future. A failure is remembered too, so a font
/// that cannot render the sentinels is reported by every reader and is not
/// retried every launch step; the atlas treats it as an unknown art version.
///
/// This class knows nothing about fingerprints, which keeps `catalog_assets`
/// free of the data layer: it only gives any asynchronous computation the
/// shape of the seam.
///
/// [GlyphAtlas]: package:catalog_assets/glyph_atlas.dart
final class ComputedGlyphArtVersion implements GlyphArtVersionSource {
  /// Creates a source answering what [compute] answers, the first time it is
  /// read.
  ComputedGlyphArtVersion(this._compute);

  final Future<String> Function() _compute;
  Future<String>? _version;

  @override
  Future<String> read() => _version ??= _compute();
}
