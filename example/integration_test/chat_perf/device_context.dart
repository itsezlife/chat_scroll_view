/// The on-device [ScenarioContext]: paced pointer input over the bench host and
/// frame capture per measured window.
library;

import 'dart:ui';

import 'package:flutter/scheduler.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../panel_perf/frame_metrics.dart';
import 'bench_host.dart';
import 'metrics.dart';
import 'registry.dart';
import 'report_document.dart';

/// Runs one scenario on [host] and collects its windows.
final class DeviceContext implements ScenarioContext {
  DeviceContext(this.host, this.scenario);

  final BenchHost host;
  final Scenario scenario;

  /// How long the first frames of a window last.
  final double firstFramesSpanMs = kFirstFramesSpanMs;

  /// Window name -> metrics, in the order measured.
  final windows = <String, Map<String, Metric>>{};

  /// Window name -> per-frame rows.
  final frames = <String, List<FrameRow>>{};

  WidgetTester get _tester => host.tester;

  @override
  Future<void> measure(
    String name,
    Future<void> Function() body, {
    Future<void> Function()? primer,
  }) async {
    if (!scenario.windows.contains(name)) {
      throw StateError('${scenario.key} did not declare window "$name"');
    }
    if (primer != null) {
      await settle();
      await primer();
    }
    // Idle before the window, so no primer or mount frame leaks into it.
    await settle();
    final timings = <FrameTiming>[];
    void onTimings(List<FrameTiming> batch) => timings.addAll(batch);
    SchedulerBinding.instance.addTimingsCallback(onTimings);
    // Measured from the binding at the start of the window, not assumed.
    final semanticsOn = SemanticsBinding.instance.semanticsEnabled;
    await body();
    // Timings arrive in batches; give the last one time to land.
    await _tester.pump(const Duration(milliseconds: 1500));
    SchedulerBinding.instance.removeTimingsCallback(onTimings);

    final rows = [
      for (final t in timings)
        FrameRow(_ms(t.buildDuration), _ms(t.rasterDuration), _ms(t.totalSpan)),
    ];
    final samples = [
      for (final r in rows)
        FrameSample(
          buildMs: r.buildMs,
          rasterMs: r.rasterMs,
          totalMs: r.totalMs,
        ),
    ];
    final (first, steady) = splitFirstFrames(samples, [
      for (final t in timings)
        t.timestampInMicroseconds(FramePhase.vsyncStart) / 1000,
    ], spanMs: firstFramesSpanMs);
    windows[name] = {
      ...windowMetrics(
        first,
        steady,
        refreshRateHz: _tester.view.display.refreshRate,
        cold: scenario.cold,
      ),
      'semantics_on': Metric(
        semanticsOn ? 1 : 0,
        kind: MetricKind.count,
        role: MetricRole.diagnostic,
      ),
    };
    frames[name] = rows;
  }

  @override
  Future<void> drag(double dy, Duration duration) async {
    // `timedDrag` moves the pointer once per 1/frequency of real time; the
    // frame policy is `fullyLive`, so the pumps are real frames.
    await _tester.timedDrag(
      host.viewport,
      Offset(0, dy),
      duration,
      frequency: 120,
    );
  }

  @override
  Future<void> settle() async {
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    do {
      await _tester.pump(const Duration(milliseconds: 16));
    } while (_tester.binding.hasScheduledFrame &&
        DateTime.now().isBefore(deadline));
  }

  static double _ms(Duration d) => d.inMicroseconds / 1000;
}
