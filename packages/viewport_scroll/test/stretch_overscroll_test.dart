import 'package:flutter_test/flutter_test.dart';
import 'package:viewport_scroll/src/stretch_overscroll.dart';

void main() {
  test('onDragEnd with velocity but zero stretch does not arm a spring', () {
    final stretch = ViewportStretchOverscroll();
    stretch.onDragEnd(2000);
    expect(stretch.isActive, isFalse);
    expect(stretch.tick(const Duration(milliseconds: 16)), isFalse);
    expect(stretch.overscroll, 0);
  });

  test('pull then onDragEnd arms a return spring', () {
    final stretch = ViewportStretchOverscroll()..pull(400, 800);
    expect(stretch.overscroll, isNot(0));
    stretch.onDragEnd(0);
    expect(stretch.isActive, isTrue);
    var elapsed = Duration.zero;
    for (var i = 0; i < 40; i++) {
      elapsed += const Duration(milliseconds: 16);
      stretch.tick(elapsed);
    }
    expect(stretch.overscroll.abs(), lessThan(0.001));
    expect(stretch.isActive, isFalse);
  });

  test('releaseIntoContent is a no-op at rest', () {
    final stretch = ViewportStretchOverscroll();
    stretch.releaseIntoContent();
    expect(stretch.isActive, isFalse);
    expect(stretch.overscroll, 0);
  });

  test('absorbImpact ignores tiny leftover velocity', () {
    final stretch = ViewportStretchOverscroll();
    stretch.absorbImpact(20);
    expect(stretch.isActive, isFalse);
    expect(stretch.overscroll, 0);
  });

  test('tiny leftover stretch does not arm a spring on drag end', () {
    final stretch = ViewportStretchOverscroll()..pull(8, 832);
    expect(stretch.overscroll.abs(), lessThan(0.004));
    stretch.onDragEnd(800);
    expect(stretch.isActive, isFalse);
    expect(stretch.overscroll, 0);
  });

  test('releaseIntoContent does not restart a running spring', () {
    final stretch = ViewportStretchOverscroll()..pull(400, 800);
    stretch.releaseIntoContent();
    stretch.tick(const Duration(milliseconds: 80));
    final mid = stretch.overscroll.abs();
    expect(mid, greaterThan(0));
    stretch.releaseIntoContent();
    stretch.tick(const Duration(milliseconds: 160));
    expect(stretch.overscroll.abs(), lessThan(mid));
  });

  test('onDragStart snaps leftover below paint threshold', () {
    final stretch = ViewportStretchOverscroll()..pull(8, 832);
    stretch.onDragStart();
    expect(stretch.overscroll, 0);
    expect(stretch.isActive, isFalse);
  });

  test('reverse fling into content drops stretch instead of springing', () {
    final stretch = ViewportStretchOverscroll()..pull(-400, 800);
    expect(stretch.overscroll, lessThan(0));
    // Finger flings down (into history) while stretch is on the newest edge.
    stretch.onDragEnd(4000);
    expect(stretch.isActive, isFalse);
    expect(stretch.overscroll, 0);
  });

  test('same-direction release absorbs then returns without slamming', () {
    final stretch = ViewportStretchOverscroll()..pull(-400, 800);
    final atRelease = stretch.overscroll;
    expect(atRelease, lessThan(0));
    stretch.onDragEnd(-5000);
    expect(stretch.isActive, isTrue);
    // First frame should deepen (or hold) the stretch — not snap toward 0.
    stretch.tick(const Duration(milliseconds: 16));
    expect(stretch.overscroll, lessThanOrEqualTo(atRelease + 0.001));
    var elapsed = const Duration(milliseconds: 16);
    for (var i = 0; i < 60; i++) {
      elapsed += const Duration(milliseconds: 16);
      stretch.tick(elapsed);
    }
    expect(stretch.overscroll.abs(), lessThan(0.001));
    expect(stretch.isActive, isFalse);
  });

  test('soft release with zero velocity settles from current stretch', () {
    final stretch = ViewportStretchOverscroll()..pull(-400, 800);
    final atRelease = stretch.overscroll.abs();
    stretch.onDragEnd(0);
    stretch.tick(const Duration(milliseconds: 16));
    // Soft spring(0): first tick stays near the release stretch.
    expect(stretch.overscroll.abs(), greaterThan(atRelease * 0.5));
  });
}
