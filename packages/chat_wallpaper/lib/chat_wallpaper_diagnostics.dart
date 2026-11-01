/// Counters a host or a test reads to learn *how much* raster work the
/// wallpaper did, never whether it drew correctly.
///
/// Observation only: nothing in the package reads these values, so they never
/// change what is drawn. They stay in release and profile builds because the
/// rule they check (a window resize or rotation rasterizes no pattern) is
/// verified on a profile build on a
/// device, where a frame's cost alone does not say which raster paid for it.
library;

/// Raster work the wallpaper has done since the last [reset].
abstract final class ChatWallpaperDiagnostics {
  /// Pattern artwork rasterized from its vector source. One per pattern per
  /// display; a window resize or rotation adds none.
  static int patternRasterizations = 0;

  /// Freeform gradient rasters computed and decoded: the keyframes a motion
  /// controller shares (on a background isolate where the platform has one)
  /// and the phase-0 raster of a fill without one.
  static int gradientRasters = 0;

  /// Sets every counter back to zero.
  static void reset() {
    patternRasterizations = 0;
    gradientRasters = 0;
  }
}
