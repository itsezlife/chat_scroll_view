import 'package:flutter_test/flutter_test.dart';
import 'package:panel_presentation/panel_presentation.dart';
import 'package:panel_presentation/testing.dart';

void main() {
  ImeInputPortContract.run('ImeInput', ImeInput.new);
  ImeInputPortContract.run('FakeImeInput', FakeImeInput.new);

  group('ImeSample', () {
    test('compares by every field', () {
      expect(
        const ImeSample(height: 1, animating: true, safeAreaBottom: 2),
        const ImeSample(height: 1, animating: true, safeAreaBottom: 2),
      );
      expect(
        const ImeSample(height: 1),
        isNot(const ImeSample(height: 1, animating: true)),
      );
      expect(
        const ImeSample(height: 1),
        isNot(const ImeSample(height: 1, safeAreaBottom: 1)),
      );
    });

    test('rejects negative extents', () {
      expect(() => ImeSample(height: -1), throwsAssertionError);
      expect(
        () => ImeSample(height: 0, safeAreaBottom: -1),
        throwsAssertionError,
      );
    });
  });

  group('FakeImeInput', () {
    test('ramps through animating readings to a settled one', () {
      final ime = FakeImeInput();
      addTearDown(ime.dispose);

      ime.rampTo(300, steps: 3);

      expect(ime.reports.map((s) => s.height), [100, 200, 300, 300]);
      expect(ime.reports.map((s) => s.animating), [true, true, true, false]);
      expect(ime.samples.value, const ImeSample(height: 300));
    });

    test('ramps down from where the keyboard stands', () {
      final ime = FakeImeInput();
      addTearDown(ime.dispose);
      ime.report(const ImeSample(height: 300));

      ime.rampTo(0, steps: 2);

      expect(ime.reports.skip(1).map((s) => s.height), [150, 0, 0]);
    });

    test('keeps the safe area on every reading of a ramp', () {
      final ime = FakeImeInput();
      addTearDown(ime.dispose);

      ime.rampTo(300, steps: 2, safeAreaBottom: 34);

      expect(ime.reports.map((s) => s.safeAreaBottom), [34, 34, 34]);
    });
  });
}
