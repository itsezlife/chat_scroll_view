/// Temporary experiment switches for the glyph-perf investigation
/// (`.scratch/panel-catalog-glyph-perf`).
///
/// Not part of the portable contract and deliberately **not** exported from
/// `panel_catalog.dart`. The switch defaults to off, so production paint is
/// unchanged. Delete this library and its call sites once the investigation
/// resolves.
library;

/// Runtime switches read by the engine on the paint path.
abstract final class PanelCatalogPerfProbe {
  /// When non-null, every unicode leaf paints this string instead of its glyph.
  ///
  /// A plain Latin letter takes the monochrome glyph path; if jank disappears
  /// with it, the color-glyph path is the culprit. Seeded from
  /// `--dart-define=PANEL_PERF_GLYPH=A` so a *cold* swap needs no code edit.
  static String? glyphOverride = switch (const String.fromEnvironment(
    'PANEL_PERF_GLYPH',
  )) {
    '' => null,
    final glyph => glyph,
  };

  /// Scroll offset of the most recent paint.
  static double lastOffset = 0;

  /// Highest scroll offset painted so far (how far a fling script travelled).
  static double maxOffset = 0;

  /// Content extent and viewport height from the most recent paint.
  static double contentExtent = 0;

  /// Viewport height from the most recent paint.
  static double viewportHeight = 0;

  /// Called by the engine each paint; keeps coverage stats for the harness.
  static void recordPaint(double offset, double extent, double viewport) {
    lastOffset = offset;
    contentExtent = extent;
    viewportHeight = viewport;
    if (offset > maxOffset) maxOffset = offset;
  }

  /// Resets coverage stats (not the switches above).
  static void resetCoverage() {
    lastOffset = 0;
    maxOffset = 0;
  }
}
