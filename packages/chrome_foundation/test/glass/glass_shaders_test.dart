/// The liquid shader's geometry: how far outside a surface it samples.
///
/// **Seam:** `GlassShaders.backdropReach`, the number the sampled backdrop
/// sizes its capture with, for surfaces of every size a surface passes
/// through while it animates.
library;

import 'dart:ui';

import 'package:chrome_foundation/src/glass/glass_style.dart';
import 'package:chrome_foundation/src/glass/shader/glass_shaders.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const style = GlassStyle(
    fill: Color(0xD920242A),
    strokeTop: Color(0x28FFFFFF),
    strokeBottom: Color(0x14FFFFFF),
    shadowColor: Color(0x00000000),
  );

  test('a surface thinner than five pixels has a reach, not an error: a '
      'sheet growing from nothing passes through every height', () {
    for (final side in [0.5, 1.0, 2.0, 4.9]) {
      final reach = GlassShaders.backdropReach(
        style: style,
        size: Size(320, side),
      );
      expect(reach, isNonNegative, reason: '$side');
      expect(reach.isFinite, isTrue, reason: '$side');
    }
  });

  test('the rim is no thinner than a pixel and no thicker than a fifth of '
      'the shorter side, the style\'s thickness between', () {
    double reach(Size size) =>
        GlassShaders.backdropReach(style: style, size: size);

    // 11 (the style's) on a large surface; a fifth of 20 on a thin one.
    expect(
      reach(const Size(320, 20)) / reach(const Size(320, 200)),
      closeTo(4 / 11, 1e-9),
    );
  });
}
