import 'package:chrome_foundation/src/glass/glass_capabilities.dart';
import 'package:chrome_foundation/src/glass/glass_quality.dart';

/// How a surface paints its backdrop. Internal: the chain is not API.
enum GlassStrategy {
  /// Captured region of the glass source, refracted by the liquid shader.
  sampledLiquid,

  /// Captured region of the glass source, blurred and tinted only.
  sampledFrost,

  /// The scene behind the surface, filtered with a backdrop filter.
  backdropFilter,

  /// The material's fill, with no backdrop read.
  flat,

  /// Nothing behind the child.
  none;

  /// Picks the strategy for one surface.
  ///
  /// [quality] is the host's ceiling and [liteMode] caps any glass at flat.
  /// With a source ([hasSource]) on a backend that can capture, the surface
  /// samples it: that read does not touch the onscreen target, so route motion
  /// does not matter. Otherwise it filters the scene, except while its route
  /// moves ([routeMoving]), when a backdrop filter would re-read and re-filter
  /// everything under it on every frame, so it paints flat. Without any filter
  /// support it paints flat.
  static GlassStrategy select({
    required GlassQuality quality,
    required bool liteMode,
    required GlassCapabilities capabilities,
    required bool hasSource,
    required bool routeMoving,
  }) {
    final effective = switch (quality) {
      GlassQuality.off => GlassQuality.off,
      _ when liteMode => GlassQuality.flat,
      _ => quality,
    };
    switch (effective) {
      case GlassQuality.off:
        return GlassStrategy.none;
      case GlassQuality.flat:
        return GlassStrategy.flat;
      case GlassQuality.fullLiquid || GlassQuality.frosted:
        if (hasSource && capabilities.sampledBackdrop) {
          return effective == GlassQuality.fullLiquid
              ? GlassStrategy.sampledLiquid
              : GlassStrategy.sampledFrost;
        }
        if (routeMoving || !capabilities.backdropFilter)
          return GlassStrategy.flat;
        return GlassStrategy.backdropFilter;
    }
  }
}
