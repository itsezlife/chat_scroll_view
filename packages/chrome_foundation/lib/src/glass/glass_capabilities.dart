import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

/// What the running backend can draw for glass.
///
/// [detect] reads the engine once; a host or a test supplies its own through
/// `GlassQualityScope.capabilities` to force a row of the fallback matrix.
@immutable
final class GlassCapabilities {
  /// Capabilities with each flag given.
  const GlassCapabilities({
    required this.sampledBackdrop,
    required this.shaderFilter,
    required this.backdropFilter,
  });

  /// What the current engine offers.
  ///
  /// Capture-based sampling needs fragment shaders over a captured image, so
  /// it is on only where `ImageFilter.shader` is supported (Impeller) and not
  /// on the web. Scene filtering stays on everywhere; a platform where it is
  /// too slow is handled by the host choosing a lower `GlassQuality`.
  factory GlassCapabilities.detect() {
    final shaders = ui.ImageFilter.isShaderFilterSupported;
    return GlassCapabilities(
      sampledBackdrop: shaders && !kIsWeb,
      shaderFilter: shaders,
      backdropFilter: true,
    );
  }

  /// Every strategy is available.
  static const GlassCapabilities all = GlassCapabilities(
    sampledBackdrop: true,
    shaderFilter: true,
    backdropFilter: true,
  );

  /// Only flat fills are available.
  static const GlassCapabilities none = GlassCapabilities(
    sampledBackdrop: false,
    shaderFilter: false,
    backdropFilter: false,
  );

  /// A region of the content can be captured to an image and drawn through a
  /// fragment shader.
  final bool sampledBackdrop;

  /// A fragment shader can be applied as a backdrop filter.
  final bool shaderFilter;

  /// The scene behind a surface can be blurred with a backdrop filter.
  final bool backdropFilter;

  /// A copy with the named flags replaced.
  GlassCapabilities copyWith({
    bool? sampledBackdrop,
    bool? shaderFilter,
    bool? backdropFilter,
  }) => GlassCapabilities(
    sampledBackdrop: sampledBackdrop ?? this.sampledBackdrop,
    shaderFilter: shaderFilter ?? this.shaderFilter,
    backdropFilter: backdropFilter ?? this.backdropFilter,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GlassCapabilities &&
          sampledBackdrop == other.sampledBackdrop &&
          shaderFilter == other.shaderFilter &&
          backdropFilter == other.backdropFilter;

  @override
  int get hashCode =>
      Object.hash(sampledBackdrop, shaderFilter, backdropFilter);

  @override
  String toString() =>
      'GlassCapabilities(sampledBackdrop: $sampledBackdrop, '
      'shaderFilter: $shaderFilter, backdropFilter: $backdropFilter)';
}
