import 'package:catalog_assets/src/atlas/bake_frame_source.dart';

/// A [BakeClock] that only moves when a test says so.
///
/// Pass [read] as the clock; advance it from a fake rasteriser to model a glyph
/// that takes time to draw.
final class ManualBakeClock {
  Duration _now = Duration.zero;

  /// The current reading.
  Duration get now => _now;

  /// Moves time forward by [by].
  void advance(Duration by) {
    assert(!by.isNegative, 'a monotonic clock does not run backwards');
    _now += by;
  }

  /// The clock function to inject.
  Duration read() => _now;
}
