/// Says which version of the system's emoji art the rasteriser draws, as an
/// opaque string: two reads that differ mean the art may have changed (an OS
/// or emoji font update) and persisted pages are out of date.
///
/// A seam, because how the version is learned is not this package's business
/// and must not need a native plugin: the intended source is a pixel
/// fingerprint of a few sentinel glyphs rendered at startup (the glyph probe),
/// with the OS version string as a supplementary part where it is meaningful.
/// Until that exists a host supplies a [FixedGlyphArtVersion].
///
/// Contract: [read] completes with the same string for the same art, however
/// often it is called, and may take several frames. It may throw; the atlas
/// reports that and treats the art as unknown (which never matches a
/// persisted set, so nothing stale is trusted).
abstract interface class GlyphArtVersionSource {
  /// The current art version.
  Future<String> read();
}

/// A [GlyphArtVersionSource] whose answer the host already knows, such as an
/// OS version string, or a value passed in to simulate an OS update on a
/// device.
final class FixedGlyphArtVersion implements GlyphArtVersionSource {
  /// Creates a source that always answers [version].
  const FixedGlyphArtVersion(this.version);

  /// The answer.
  final String version;

  @override
  Future<String> read() async => version;
}
