import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

ChromeMotionData? _seen;

Widget _probe() => Builder(
  builder: (context) {
    _seen = ChromeMotionScope.of(context);
    return const SizedBox();
  },
);

void main() {
  setUp(() => _seen = null);

  group('without a scope', () {
    testWidgets('resolves the standard motion at normal speed', (tester) async {
      await tester.pumpWidget(_probe());
      expect(_seen!.motion, const ChromeMotion.standard());
      expect(_seen!.speed, ChromeMotionSpeed.normal);
      expect(
        _seen!.durationOf(MotionRole.listTransition),
        const Duration(milliseconds: 250),
      );
    });
  });

  group('speed', () {
    testWidgets('scaled speed shortens every role', (tester) async {
      await tester.pumpWidget(
        ChromeMotionScope(
          speed: const ChromeMotionSpeed.times(2),
          child: _probe(),
        ),
      );
      expect(
        _seen!.durationOf(MotionRole.listTransition),
        const Duration(milliseconds: 125),
      );
      expect(
        _seen!.curveOf(MotionRole.listTransition),
        ChromeMotion.androidListCurve,
      );
    });

    testWidgets('instant makes every role zero', (tester) async {
      await tester.pumpWidget(
        ChromeMotionScope(speed: ChromeMotionSpeed.instant, child: _probe()),
      );
      for (final role in MotionRole.values) {
        expect(_seen!.durationOf(role), Duration.zero, reason: '$role');
        expect(_seen!.specOf(role).duration, Duration.zero, reason: '$role');
      }
    });

    testWidgets('a speed change rebuilds dependents', (tester) async {
      Widget build(ChromeMotionSpeed speed) =>
          ChromeMotionScope(speed: speed, child: _probe());
      await tester.pumpWidget(build(ChromeMotionSpeed.normal));
      expect(
        _seen!.durationOf(MotionRole.fade),
        const Duration(milliseconds: 200),
      );
      await tester.pumpWidget(build(ChromeMotionSpeed.instant));
      expect(_seen!.durationOf(MotionRole.fade), Duration.zero);
    });
  });

  group('per-role override', () {
    testWidgets('a scope motion replaces one role and speed still applies', (
      tester,
    ) async {
      const slowSearch = MotionSpec(Duration(seconds: 1), Curves.easeIn);
      await tester.pumpWidget(
        ChromeMotionScope(
          motion: const ChromeMotion.standard().copyWith(search: slowSearch),
          speed: const ChromeMotionSpeed.times(2),
          child: _probe(),
        ),
      );
      expect(
        _seen!.durationOf(MotionRole.search),
        const Duration(milliseconds: 500),
      );
      expect(_seen!.curveOf(MotionRole.search), Curves.easeIn);
      expect(
        _seen!.durationOf(MotionRole.fade),
        const Duration(milliseconds: 100),
      );
    });
  });

  group('nesting', () {
    testWidgets('an inner scope with only a speed keeps the outer motion', (
      tester,
    ) async {
      const slowSearch = MotionSpec(Duration(seconds: 1), Curves.easeIn);
      await tester.pumpWidget(
        ChromeMotionScope(
          motion: const ChromeMotion.standard().copyWith(search: slowSearch),
          child: ChromeMotionScope(
            speed: ChromeMotionSpeed.instant,
            child: _probe(),
          ),
        ),
      );
      expect(_seen!.motion[MotionRole.search], slowSearch);
      expect(_seen!.speed, ChromeMotionSpeed.instant);
    });

    testWidgets('an inner scope with only motion keeps the outer speed', (
      tester,
    ) async {
      await tester.pumpWidget(
        ChromeMotionScope(
          speed: ChromeMotionSpeed.instant,
          child: ChromeMotionScope(
            motion: const ChromeMotion.standard(),
            child: _probe(),
          ),
        ),
      );
      expect(_seen!.speed, ChromeMotionSpeed.instant);
    });
  });
}
