import 'package:catalog_assets/glyph_atlas.dart';
import 'package:flutter_test/flutter_test.dart';

// The default pace, the most a frame ever bakes.
final _max = const BakePacing().maxGlyphsPerFrame;

// A 120 Hz display.
const _budget = Duration(microseconds: 8333);

Duration _fraction(double of) =>
    Duration(microseconds: (_budget.inMicroseconds * of).round());

void main() {
  late BakeGovernor governor;

  setUp(() => governor = BakeGovernor());

  void observe(double budgetFraction, {int times = 1}) {
    for (var i = 0; i < times; i++) {
      governor.observe(cost: _fraction(budgetFraction), budget: _budget);
    }
  }

  test('starts at the default pace, the most it ever bakes', () {
    expect(governor.glyphsPerFrame, _max);
  });

  test('the default unit is eight glyphs, measured to fit a 120 Hz frame', () {
    // One strip is one snapshot on the raster thread, which frame timings do
    // not report, so this ceiling is the unit in practice (see BakePacing).
    expect(const BakePacing().maxGlyphsPerFrame, 8);
  });

  test('cheap frames keep the pace at the maximum', () {
    observe(0.2, times: 10);

    expect(governor.glyphsPerFrame, _max);
  });

  test('an expensive frame lowers the pace', () {
    observe(1.2);

    expect(governor.glyphsPerFrame, lessThan(_max));
  });

  test('a frame that only just fits the budget also lowers the pace', () {
    // Anything near the budget is one slow frame away from a drop.
    observe(0.9);

    expect(governor.glyphsPerFrame, lessThan(_max));
  });

  test('the pace falls quickly under sustained pressure, to one glyph', () {
    observe(1.5, times: 6);

    expect(governor.glyphsPerFrame, 1);
  });

  test('it never stops baking by itself', () {
    observe(3, times: 100);

    expect(governor.glyphsPerFrame, greaterThanOrEqualTo(1));
  });

  test('cheap frames raise the pace again, gradually', () {
    observe(1.5, times: 6);
    expect(governor.glyphsPerFrame, 1);

    observe(0.2);
    final first = governor.glyphsPerFrame;
    observe(0.2);

    expect(first, greaterThan(1));
    expect(governor.glyphsPerFrame, greaterThan(first));
  });

  test('the pace never exceeds the maximum', () {
    observe(1.5);
    observe(0.2, times: 50);

    expect(governor.glyphsPerFrame, _max);
  });

  test('a middling frame holds the pace', () {
    observe(1.5);
    final held = governor.glyphsPerFrame;

    observe(0.7, times: 5);

    expect(governor.glyphsPerFrame, held);
  });

  test(
    'the budget scales the thresholds: a cost fine at 60 Hz is not at 120',
    () {
      const cost = Duration(milliseconds: 10);

      governor.observe(cost: cost, budget: const Duration(microseconds: 16667));
      final at60 = governor.glyphsPerFrame;
      governor.observe(cost: cost, budget: _budget);

      expect(at60, _max);
      expect(governor.glyphsPerFrame, lessThan(_max));
    },
  );

  test('a measurement that cannot vouch for a frame may lower, not raise', () {
    governor.observe(cost: _fraction(1.5), budget: _budget, mayRise: false);
    final lowered = governor.glyphsPerFrame;

    governor.observe(cost: _fraction(0.1), budget: _budget, mayRise: false);

    expect(lowered, lessThan(_max));
    expect(governor.glyphsPerFrame, lowered);
  });

  test('the limits are configurable', () {
    final small = BakeGovernor(
      pacing: const BakePacing(maxGlyphsPerFrame: 4, minGlyphsPerFrame: 2),
    );

    expect(small.glyphsPerFrame, 4);
    for (var i = 0; i < 10; i++) {
      small.observe(cost: _fraction(2), budget: _budget);
    }
    expect(small.glyphsPerFrame, 2);
  });
}
