import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/chat_perf/keyboard_ramp.dart';
import '../../integration_test/chat_perf/metrics.dart';

/// A trace of a still window: [insets] in physical px, the pad following them
/// one for one, the anchor shifting by the pad change, as invariant 16 says.
List<RampSample> _compensated(
  List<num> insets, {
  double dpr = 2,
  double anchor0 = 500,
  int id = 7,
}) {
  final out = <RampSample>[];
  for (final (i, px) in insets.indexed) {
    final pad = px / dpr;
    out.add(
      RampSample(
        tMs: i * 8.0,
        insetPx: px.toDouble(),
        padDp: pad,
        anchorId: id,
        anchorOffsetDp: anchor0 - (pad - insets.first / dpr),
      ),
    );
  }
  return out;
}

RampSample _with(RampSample s, {int? anchorId, double anchorShiftDp = 0}) =>
    RampSample(
      tMs: s.tMs,
      insetPx: s.insetPx,
      padDp: s.padDp,
      anchorId: anchorId ?? s.anchorId,
      anchorOffsetDp: s.anchorOffsetDp + anchorShiftDp,
    );

/// A real-IME trace: one frame every [vsyncMs] (a frame requested every
/// vsync), the inset moving on every [moveEvery]th frame for [moves] moves.
List<RampSample> _imeTrace({
  required double vsyncMs,
  int moveEvery = 1,
  int moves = 20,
}) {
  final out = <RampSample>[];
  var inset = 0.0;
  for (var i = 0; i < moves * moveEvery + 4; i++) {
    if (i > 1 && i <= moves * moveEvery + 1 && (i - 1) % moveEvery == 0) {
      inset += 10;
    }
    out.add(
      RampSample(
        tMs: i * vsyncMs,
        vsyncMs: 1000 + i * vsyncMs,
        insetPx: inset,
        padDp: inset / 2,
        anchorId: 7,
        anchorOffsetDp: 500 - inset / 2,
      ),
    );
  }
  return out;
}

void main() {
  group('InsetCurve', () {
    test('android_ramp opens from 0 to 1 over about 360 ms', () {
      final c = InsetCurveProfile.androidRamp.open;
      expect(c.at(0), 0);
      expect(c.at(c.durationMs), 1);
      expect(c.durationMs, closeTo(358, 2));
      expect(c.at(c.durationMs + 100), 1);
    });

    test('the open ramp rises fast and eases out', () {
      final c = InsetCurveProfile.androidRamp.open;
      expect(c.at(c.durationMs / 4), greaterThan(0.5));
      expect(c.at(c.durationMs / 2), greaterThan(0.85));
    });

    test('the close ramp falls from 1 to 0 and is monotone', () {
      final c = InsetCurveProfile.androidRamp.close;
      expect(c.at(0), 1);
      expect(c.at(c.durationMs), 0);
      var last = 1.0;
      for (var t = 0.0; t <= c.durationMs; t += 5) {
        expect(c.at(t), lessThanOrEqualTo(last));
        last = c.at(t);
      }
    });

    test('scaled keeps the shape at a fraction of the height', () {
      final c = InsetCurveProfile.androidRamp.open.scaled(0.25);
      expect(c.at(c.durationMs), closeTo(0.25, 1e-9));
    });
  });

  group('rampMetrics', () {
    final insets = [0.0, 0, 100, 300, 500, 600, 600, 600];

    test('a compensated trace has no engine error and no jump', () {
      final m = rampMetrics(_compensated(insets), expectedFrames: 4);
      expect(m['engine.comp_error_dp']!.value, closeTo(0, 1e-9));
      expect(m['jump.messages']!.value, 0);
    });

    test('an uncompensated frame shows as engine error', () {
      final s = _compensated(insets);
      s[4] = _with(s[4], anchorShiftDp: 12);
      final m = rampMetrics(s, expectedFrames: 4);
      // The error enters on frame 4 and leaves on frame 5.
      expect(m['engine.comp_error_dp']!.value, closeTo(12, 1e-9));
    });

    test('anchor id changes count as jumps', () {
      final s = _compensated(insets);
      for (var i = 5; i < s.length; i++) {
        s[i] = _with(s[i], anchorId: 8);
      }
      final m = rampMetrics(s, expectedFrames: 4);
      expect(m['jump.messages']!.value, 1);
    });

    test('first inset and duration come from the first and last change', () {
      final m = rampMetrics(_compensated(insets), expectedFrames: 4);
      // First change at sample 2 (16 ms), last at sample 5 (40 ms).
      expect(m['ramp.first_inset_ms']!.value, 16);
      expect(m['ramp.duration_ms']!.value, 24);
    });

    test('delivery is distinct changed frames over expected frames', () {
      final m = rampMetrics(_compensated(insets), expectedFrames: 8);
      // Four changes (100, 300, 500, 600) of eight expected.
      expect(m['ramp.delivery']!.value, 0.5);
      expect(m['ramp.delivery']!.role, MetricRole.headline);
    });

    test('pad overshoot is the swing past the settled value, opening', () {
      final s = _compensated([0, 200, 400, 300, 300]);
      final m = rampMetrics(s, expectedFrames: 2);
      expect(m['host.pad_overshoot_dp']!.value, closeTo(50, 1e-9));
    });

    test('pad overshoot is the swing past the settled value, closing', () {
      final s = _compensated([400, 200, 0, 100, 100]);
      final m = rampMetrics(s, expectedFrames: 2);
      expect(m['host.pad_overshoot_dp']!.value, closeTo(50, 1e-9));
    });

    test('an empty trace reports nothing to judge', () {
      expect(rampMetrics([], expectedFrames: 4), isEmpty);
    });
  });

  group('pairedControlMetrics', () {
    test('compensated ends have no error and no jump', () {
      final m = pairedControlMetrics(
        withRamp: const RampEnd(anchorId: 5, anchorOffsetDp: 300, padDp: 458),
        control: const RampEnd(anchorId: 5, anchorOffsetDp: 600, padDp: 158),
      );
      expect(m['engine.comp_error_dp']!.value, closeTo(0, 1e-9));
      expect(m['jump.messages']!.value, 0);
    });

    test('a different end anchor id is a jump of that many messages', () {
      final m = pairedControlMetrics(
        withRamp: const RampEnd(anchorId: 5, anchorOffsetDp: 0, padDp: 0),
        control: const RampEnd(anchorId: 9, anchorOffsetDp: 0, padDp: 0),
      );
      expect(m['jump.messages']!.value, 4);
      expect(m.containsKey('engine.comp_error_dp'), isFalse);
    });
  });

  group('imeRampMetrics', () {
    const budget = 1000 / 120;

    test('a 60 Hz ramp that moves every vsync delivers fully', () {
      final m = imeRampMetrics(
        _imeTrace(vsyncMs: 1000 / 60),
        launchBudgetMs: budget,
      );
      expect(m['ramp.vsync_ms']!.value, closeTo(1000 / 60, 1e-9));
      expect(m['ramp.delivery']!.value, closeTo(1, 0.1));
      // Against the launch's 120 Hz it reads as half the frames.
      expect(m['ramp.delivery_at_launch_rate']!.value, closeTo(0.5, 0.05));
      expect(m['ramp.delivery_at_launch_rate']!.role, MetricRole.diagnostic);
      expect(m['ramp.delivery']!.role, MetricRole.headline);
    });

    test('a 120 Hz display with an inset every other vsync reads half', () {
      final m = imeRampMetrics(
        _imeTrace(vsyncMs: budget, moveEvery: 2),
        launchBudgetMs: budget,
      );
      expect(m['ramp.vsync_ms']!.value, closeTo(budget, 1e-9));
      expect(m['ramp.delivery']!.value, closeTo(0.5, 0.05));
    });

    test('without vsync times it falls back to the launch budget', () {
      final trace = [
        for (final s in _imeTrace(vsyncMs: 1000 / 60))
          RampSample(
            tMs: s.tMs,
            insetPx: s.insetPx,
            padDp: s.padDp,
            anchorId: s.anchorId,
            anchorOffsetDp: s.anchorOffsetDp,
          ),
      ];
      final m = imeRampMetrics(trace, launchBudgetMs: budget);
      expect(m.containsKey('ramp.vsync_ms'), isFalse);
      expect(m['ramp.delivery']!.value, closeTo(0.5, 0.05));
    });
  });

  group('observedVsyncMs', () {
    test('is the median frame gap inside the ramp only', () {
      final trace = _imeTrace(vsyncMs: 1000 / 60, moves: 5);
      // A long idle gap after the ramp does not count.
      final idle = trace.last;
      final withIdle = [
        ...trace,
        RampSample(
          tMs: idle.tMs + 500,
          vsyncMs: idle.vsyncMs! + 500,
          insetPx: idle.insetPx,
          padDp: idle.padDp,
          anchorId: idle.anchorId,
          anchorOffsetDp: idle.anchorOffsetDp,
        ),
      ];
      expect(observedVsyncMs(withIdle), closeTo(1000 / 60, 1e-9));
    });

    test('is null without a ramp or with too few gaps', () {
      expect(observedVsyncMs(_imeTrace(vsyncMs: 8, moves: 0)), isNull);
      expect(observedVsyncMs(_imeTrace(vsyncMs: 8, moves: 2)), isNull);
    });
  });
}
