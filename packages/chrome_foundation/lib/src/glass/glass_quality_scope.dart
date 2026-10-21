import 'package:chrome_foundation/src/glass/glass_capabilities.dart';
import 'package:chrome_foundation/src/glass/glass_quality.dart';
import 'package:flutter/widgets.dart';

/// The host's glass policy for a subtree: the quality ceiling, the lite-mode
/// flag and, optionally, the capabilities to assume.
///
/// Optional: with no scope a surface draws at [GlassQuality.fullLiquid] on
/// the detected capabilities, so a host that never limits glass supplies
/// nothing. Scopes nest; the nearest one wins as a whole.
class GlassQualityScope extends InheritedWidget {
  /// A policy for [child].
  const GlassQualityScope({
    required super.child,
    this.quality = GlassQuality.fullLiquid,
    this.liteMode = false,
    this.capabilities,
    super.key,
  });

  /// The richest glass the host allows.
  final GlassQuality quality;

  /// The host's low-power flag. While true, glass paints flat (or nothing,
  /// under [GlassQuality.off]) whatever [quality] says.
  final bool liteMode;

  /// Capabilities to assume instead of `GlassCapabilities.detect`, for a host
  /// that has measured a device or a test that forces a backend.
  final GlassCapabilities? capabilities;

  /// The nearest policy at [context], or null outside any scope. Depends on
  /// the scope.
  static GlassQualityScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GlassQualityScope>();

  @override
  bool updateShouldNotify(GlassQualityScope oldWidget) =>
      quality != oldWidget.quality ||
      liteMode != oldWidget.liteMode ||
      capabilities != oldWidget.capabilities;
}
