import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/animation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const motion = ChromeMotion.standard();

  test('a bulletin appears over 255 ms, ease-out quad', () {
    expect(
      motion[MotionRole.bulletinShow],
      const MotionSpec(Duration(milliseconds: 255), Curves.easeOutQuad),
    );
  });

  test('a bulletin leaves over 175 ms, ease-in quad', () {
    expect(
      motion[MotionRole.bulletinHide],
      const MotionSpec(Duration(milliseconds: 175), Curves.easeInQuad),
    );
  });

  test('copyWith replaces the bulletin roles', () {
    const spec = MotionSpec(Duration(milliseconds: 300), Curves.easeOut);
    final next = motion.copyWith(bulletinShow: spec, bulletinHide: spec);
    expect(next[MotionRole.bulletinShow], spec);
    expect(next[MotionRole.bulletinHide], spec);
    expect(next[MotionRole.fade], motion[MotionRole.fade]);
  });

  test('an instant speed removes both', () {
    const data = ChromeMotionData(speed: ChromeMotionSpeed.instant);
    expect(data.durationOf(MotionRole.bulletinShow), Duration.zero);
    expect(data.durationOf(MotionRole.bulletinHide), Duration.zero);
  });
}
