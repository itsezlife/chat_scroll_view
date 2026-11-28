/// The timing of a surface springing out of its source: the context menu's
/// spring, its cut and start scale, and the surface's own fades.
///
/// **Seam:** `ChromeSourceSpringTiming`.
library;

import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/animation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const ease = Cubic(0.42, 0, 0.58, 1);

  test('the open: a spring of damping 104 cut at 0.42 s, from scale 0.01', () {
    expect(ChromeSourceSpringTiming.spring.mass, 1);
    expect(ChromeSourceSpringTiming.spring.stiffness, 900);
    expect(ChromeSourceSpringTiming.spring.damping, 104);
    expect(
      ChromeSourceSpringTiming.springCut,
      const Duration(milliseconds: 420),
    );
    expect(ChromeSourceSpringTiming.startScale, 0.01);
  });

  test('the fades: content in over 0.15 s and out over 0.16 s, actions in '
      'over 0.05 s; the close 0.2 s; all on the ease in-out', () {
    expect(
      ChromeSourceSpringTiming.contentShowFade,
      const MotionSpec(Duration(milliseconds: 150), ease),
    );
    expect(
      ChromeSourceSpringTiming.contentHideFade,
      const MotionSpec(Duration(milliseconds: 160), ease),
    );
    expect(
      ChromeSourceSpringTiming.actionsShowFade,
      const MotionSpec(Duration(milliseconds: 50), ease),
    );
    expect(
      ChromeSourceSpringTiming.close,
      const MotionSpec(Duration(milliseconds: 200), ease),
    );
  });

  test('a change of the content resizes it over 0.5 s', () {
    expect(
      ChromeSourceSpringTiming.change,
      const MotionSpec(Duration(milliseconds: 500), Curves.easeInOut),
    );
  });
}
