import 'dart:ui' show Color;

import 'package:chrome_foundation/src/motion/spoiler_particle_motion.dart';
import 'package:chrome_foundation/src/palette/chrome_palette.dart';
import 'package:meta/meta.dart';

/// Colour and particle motion of a hidden spoiler.
///
/// The particles are drawn in the text colour by default, as in the reference
/// clients, so [color] is null until a host overrides it. Nothing that
/// renders markdown reads this group: a host passes the resolved values into
/// that renderer's own theme.
@immutable
final class SpoilerTokens {
  /// A spoiler token group; [color] null follows the text colour.
  const SpoilerTokens({
    this.color,
    this.particles = SpoilerParticleMotion.standard,
  });

  /// The default group: follow the text colour, move as
  /// [SpoilerParticleMotion.standard].
  ///
  /// Takes [palette] for the shape every group shares; the spoiler colour is
  /// a role of the text it hides, not of the palette.
  // ignore: avoid_unused_constructor_parameters
  factory SpoilerTokens.fromPalette(ChromePalette palette) =>
      const SpoilerTokens();

  /// The particle colour, or null to follow the colour of the hidden text.
  final Color? color;

  /// How the particles move.
  final SpoilerParticleMotion particles;

  /// The particle colour over text drawn in [text]: the override, if any.
  Color colorOver(Color text) => color ?? text;

  /// A copy with the named fields replaced; [followingText] removes an
  /// override.
  SpoilerTokens copyWith({Color? color, SpoilerParticleMotion? particles}) =>
      SpoilerTokens(
        color: color ?? this.color,
        particles: particles ?? this.particles,
      );

  /// A copy that follows the text colour again.
  SpoilerTokens followingText() => SpoilerTokens(particles: particles);

  /// Interpolates between [a] and [b].
  ///
  /// Two overrides blend. An override against "follow the text" has nothing
  /// to blend towards, and the particle motion is not interpolable: both
  /// switch at the middle.
  // Flutter's `T.lerp(a, b, t)` shape; a constructor cannot take two sources.
  // ignore: prefer_constructors_over_static_methods
  static SpoilerTokens lerp(SpoilerTokens a, SpoilerTokens b, double t) {
    final from = a.color;
    final to = b.color;
    return SpoilerTokens(
      color: from != null && to != null
          ? Color.lerp(from, to, t)
          : (t < 0.5 ? from : to),
      particles: t < 0.5 ? a.particles : b.particles,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SpoilerTokens &&
          color == other.color &&
          particles == other.particles;

  @override
  int get hashCode => Object.hash(color, particles);

  @override
  String toString() => 'SpoilerTokens(color: $color, $particles)';
}
