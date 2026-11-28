/// The timing of a surface springing out of its source: the content's own
/// fades and change (the spring, its cut and the close are the context
/// menu's, `AppearMotion$Spring`).
///
/// **Seam:** `ChromeSourceSpringTiming`.
library;

import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/animation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const ease = Cubic(0.42, 0, 0.58, 1);

  test('the content fades in over 0.15 s and out over 0.16 s on the ease '
      'in-out', () {
    expect(
      ChromeSourceSpringTiming.contentShowFade,
      const MotionSpec(Duration(milliseconds: 150), ease),
    );
    expect(
      ChromeSourceSpringTiming.contentHideFade,
      const MotionSpec(Duration(milliseconds: 160), ease),
    );
  });

  test('a change of the content resizes it over 0.5 s', () {
    expect(
      ChromeSourceSpringTiming.change,
      const MotionSpec(Duration(milliseconds: 500), Curves.easeInOut),
    );
  });
}
