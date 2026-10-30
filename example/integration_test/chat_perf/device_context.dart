/// The on-device [ScenarioContext]: paced pointer input over the bench host and
/// frame capture per measured window.
library;

import 'dart:ui';

import 'package:flutter/scheduler.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../panel_perf/frame_metrics.dart';
import 'bench_host.dart';
import 'churn.dart';
import 'metrics.dart';
import 'registry.dart';
import 'report_document.dart';

/// Runs one scenario on [host] and collects its windows.
final class DeviceContext implements ChurnContext {
  DeviceContext(this.host, this.scenario);

  @override
  final BenchHost host;
  final Scenario scenario;

  /// How long the first frames of a window last.
  final double firstFramesSpanMs = kFirstFramesSpanMs;

  /// Window name -> metrics, in the order measured.
  final windows = <String, Map<String, Metric>>{};

  /// Window name -> per-frame rows.
  final frames = <String, List<FrameRow>>{};

  /// Metrics reported by the scenario for the open window.
  final _extras = <String, Map<String, Metric>>{};

  @override
  void report(String name, Map<String, Metric> metrics) =>
      (_extras[name] ??= {}).addAll(metrics);

  WidgetTester get _tester => host.tester;

  ChurnFrame _sample(int index, Stopwatch clock) {
    final controller = host.controller;
    final bottoms = host.probe.visibleBottoms(host.viewportRect);
    return ChurnFrame(
      index: index,
      tMs: clock.elapsedMicroseconds / 1000,
      anchorId: controller.anchorMessageId,
      anchorOffsetDp: controller.anchorPixelOffset,
      isAtTail: controller.isAtTail.value,
      bandBottomDp: bottoms.isEmpty
          ? null
          : bottoms.values.reduce((a, b) => a > b ? a : b),
      placeholders: host.probe.placeholders,
    );
  }

  @override
  Future<void> seat(int id, {double alignment = 0.5}) async {
    host.controller.jumpTo(id, alignment: alignment);
    await settle();
    // Chunk fetches run on timers, outside the frame loop: wait for the
    // placeholders to give way.
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (host.probe.placeholders > 0 && DateTime.now().isBefore(deadline)) {
      await _tester.pump(const Duration(milliseconds: 16));
    }
    await settle();
  }

  @override
  Future<List<ChurnFrame>> runSchedule(
    FrameSchedule schedule, {
    int preRoll = kPreRollFrames,
    int postRoll = kPostRollFrames,
  }) async {
    final clock = Stopwatch()..start();
    final out = <ChurnFrame>[];
    final last = schedule.lastFrame + postRoll;
    for (var f = -preRoll; f <= last; f++) {
      if (f >= 0) {
        for (final action in schedule.actionsAt(f)) {
          action();
        }
      }
      await _tester.pump(const Duration(milliseconds: 16));
      out.add(_sample(f, clock));
    }
    final settled = !_tester.binding.hasScheduledFrame;
    report(_openWindow!, {'settled': settledMetric(settled: settled)});
    return out;
  }

  @override
  Future<List<ChurnFrame>> recordFrames(Future<void> Function() body) async {
    final clock = Stopwatch()..start();
    final out = <ChurnFrame>[];
    var recording = true;
    void tick(Duration _) {
      if (!recording) return;
      out.add(_sample(out.length, clock));
      SchedulerBinding.instance.addPostFrameCallback(tick);
    }

    SchedulerBinding.instance.addPostFrameCallback(tick);
    await body();
    recording = false;
    return out;
  }

  @override
  Future<void> fling(double dy, double velocity) =>
      _tester.fling(host.viewport, Offset(0, dy), velocity);

  String? _openWindow;

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
    _openWindow = name;
    await body();
    _openWindow = null;
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
      ...?_extras.remove(name),
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
