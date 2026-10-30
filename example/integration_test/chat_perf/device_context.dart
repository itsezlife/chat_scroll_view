/// The on-device [ScenarioContext]: paced pointer input over the bench host and
/// frame capture per measured window.
library;

import 'dart:async';
import 'dart:ui';

import 'package:flutter/scheduler.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../panel_perf/frame_metrics.dart';
import 'metrics.dart';
import 'perf_host.dart';
import 'registry.dart';
import 'report_document.dart';

/// Runs one scenario on [host] and collects its windows.
final class DeviceContext implements ScenarioContext {
  DeviceContext(this.host, this.scenario);

  final PerfHost host;
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
    await _pumpUntilIdle();
  }

  @override
  Future<({Duration time, int frames})> settleTimed() async {
    final sw = Stopwatch()..start();
    final frames = await _pumpUntilIdle();
    return (time: sw.elapsed, frames: frames);
  }

  /// Pumps real frames until none is scheduled; returns how many ran.
  Future<int> _pumpUntilIdle() async {
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    var frames = 0;
    do {
      await _tester.pump(const Duration(milliseconds: 16));
      frames++;
    } while (_tester.binding.hasScheduledFrame &&
        DateTime.now().isBefore(deadline));
    return frames;
  }

  @override
  int get history => host.history;

  @override
  int get anchorId => host.controller.anchorMessageId;

  final _clock = Stopwatch()..start();
  int _pointer = 100;

  /// A paced pointer stream: down, [freq] moves a second spread over
  /// [duration] (real time, nominal timestamps on a monotonic clock), up. The
  /// timestamps are what the velocity tracker reads, so the release velocity
  /// does not depend on frame jitter.
  Future<void> _stream(
    Offset start,
    Offset offset,
    Duration duration, {
    double freq = 60,
  }) async {
    final intervals = duration.inMicroseconds * freq ~/ 1e6;
    assert(intervals > 1, 'a stream needs at least two intervals');
    final step = Duration(microseconds: 1e6 ~/ freq);
    final pointer = TestPointer(_pointer++);
    final t0 = _clock.elapsed;
    await _tester.sendEventToBinding(pointer.down(start, timeStamp: t0));
    for (var t = 0; t <= intervals; t++) {
      if (t > 0) await _tester.pump(step);
      await _tester.sendEventToBinding(
        pointer.move(
          start + offset * (t / intervals),
          timeStamp: t0 + duration * t ~/ intervals,
        ),
      );
    }
    await _tester.sendEventToBinding(pointer.up(timeStamp: t0 + duration));
  }

  @override
  Future<void> fling(double dy, Duration duration) =>
      _stream(_tester.getCenter(host.viewport), Offset(0, dy), duration);

  @override
  Future<void> touch(Duration hold) async {
    final pointer = TestPointer(_pointer++);
    final at = _tester.getCenter(host.viewport);
    await _tester.sendEventToBinding(
      pointer.down(at, timeStamp: _clock.elapsed),
    );
    await idle(hold);
    await _tester.sendEventToBinding(pointer.up(timeStamp: _clock.elapsed));
  }

  @override
  Future<void> idle(Duration duration) async {
    final end = DateTime.now().add(duration);
    while (DateTime.now().isBefore(end)) {
      await _tester.pump(const Duration(milliseconds: 16));
    }
  }

  @override
  Future<int> jumpTo(int id) async {
    host.controller.jumpTo(id);
    return _pumpUntilIdle();
  }

  @override
  Future<({int frames, int anchorId, double anchorOffset})> animateTo(
    int id,
    Duration duration,
  ) async {
    final controller = host.controller;
    var done = false;
    unawaited(
      controller
          .animateTo(id, duration: duration, highlight: false)
          .whenComplete(() => done = true),
    );
    var frames = 0;
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (!done && DateTime.now().isBefore(deadline)) {
      await _tester.pump(const Duration(milliseconds: 16));
      frames++;
    }
    await _pumpUntilIdle();
    return (
      frames: frames,
      anchorId: controller.anchorMessageId,
      anchorOffset: controller.anchorPixelOffset,
    );
  }

  @override
  Future<int> jumpToNewest() => jumpTo(host.history - 1);

  @override
  Future<void> scrollbarDrag(double dy, Duration duration) async {
    host.controller.flashScrollbar();
    await _tester.pump(const Duration(milliseconds: 100));
    final rect = _tester.getRect(host.viewport);
    // The mobile thumb is 4 px wide, 3 px in from the trailing edge, centred
    // on the track at mid-history; its touch target reaches 20 px in.
    await _stream(
      Offset(rect.right - 8, rect.center.dy),
      Offset(0, dy),
      duration,
    );
  }

  @override
  Future<int> countAnchorJumps(
    Future<void> Function() body, {
    int thresholdMessages = 200,
  }) async {
    var jumps = 0;
    var running = true;
    var last = host.controller.anchorMessageId;
    void sample(Duration _) {
      if (!running) return;
      final now = host.controller.anchorMessageId;
      if ((now - last).abs() > thresholdMessages) jumps++;
      last = now;
      SchedulerBinding.instance.addPostFrameCallback(sample);
    }

    SchedulerBinding.instance.addPostFrameCallback(sample);
    try {
      await body();
    } finally {
      running = false;
    }
    return jumps;
  }

  @override
  void record(String window, String name, Metric metric) {
    final w = windows[window];
    if (w == null) {
      throw StateError('${scenario.key} has not measured window "$window"');
    }
    w[name] = metric;
  }

  static double _ms(Duration d) => d.inMicroseconds / 1000;
}
