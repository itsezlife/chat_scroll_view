/// The on-device [GestureDriver]: live-time held pointers over the bench host.
library;

import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'bench_host.dart';
import 'corpus.dart';
import 'corpus_rich.dart';
import 'gesture_driver.dart';
import 'metrics.dart';

/// One pointer on the device: timestamps come from the host clock, so a hold
/// of 600 ms is 600 ms of wall time with frames running.
final class _LivePointer implements PointerStream {
  _LivePointer(this._host, this._gesture) : _downAt = _host.clock.elapsed;

  final BenchHost _host;
  final TestGesture _gesture;
  final Duration _downAt;

  @override
  Future<Duration?> hold(Duration duration, {bool Function()? watch}) async {
    Duration? held;
    final end = _host.clock.elapsed + duration;
    while (_host.clock.elapsed < end) {
      await _host.tester.pump();
      if (held == null && (watch?.call() ?? false)) {
        held = _host.clock.elapsed - _downAt;
      }
    }
    return held;
  }

  @override
  Future<void> moveBy(Offset delta, {required int frames}) async {
    final step = delta / frames.toDouble();
    for (var i = 0; i < frames; i++) {
      await _gesture.moveBy(step, timeStamp: _host.clock.elapsed);
      await _host.tester.pump();
    }
  }

  @override
  Future<void> up() async {
    await _gesture.up(timeStamp: _host.clock.elapsed);
    _host.lastPointerUpAt = _host.clock.elapsed;
    await _host.tester.pump();
  }
}

/// Drives [host]; [windows] is the owning context's measured windows.
final class DeviceGestures implements GestureDriver {
  DeviceGestures(this.host, this.windows);

  final BenchHost host;
  final Map<String, Map<String, Metric>> windows;

  WidgetTester get _tester => host.tester;

  @override
  Rect get viewportRect => _tester.getRect(host.viewport);

  @override
  Rect rowRect(BenchTarget target) => host.rectOf(host.rowKeys[target]!);

  @override
  Rect bodyRect(BenchTarget target) => host.rectOf(host.bodyKeys[target]!);

  @override
  Rect? bodyRectIfMounted(BenchTarget target) {
    final box = host.bodyKeys[target]!.currentContext?.findRenderObject();
    return switch (box) {
      final RenderBox b when b.attached =>
        b.localToGlobal(Offset.zero) & b.size,
      _ => null,
    };
  }

  @override
  Future<void> seat(int id) async {
    if (id >= host.source.corpus.count) {
      throw StateError('message $id is beyond the history');
    }
    host.controller.jumpTo(id, alignment: 0.5);
    await _settle();
  }

  @override
  Future<void> seatTarget(BenchTarget target) async {
    if (host.source.corpus.profile != BenchProfile.rich ||
        host.source.corpus.count < kRichProfileExtent) {
      throw StateError(
        'the rich profile needs a history of at least $kRichProfileExtent',
      );
    }
    await seat(target.id);
    final row = rowRect(target);
    final view = viewportRect;
    if (!view.contains(row.topLeft) || !view.contains(row.bottomRight)) {
      throw StateError('$target is not fully visible: $row in $view');
    }
  }

  @override
  Future<PointerStream> down(Offset global) async {
    final gesture = await _tester.startGesture(global);
    await _tester.pump();
    return _LivePointer(host, gesture);
  }

  @override
  Future<void> tap(
    Offset global, {
    Duration hold = const Duration(milliseconds: 50),
  }) async {
    final pointer = await down(global);
    await pointer.hold(hold);
    await pointer.up();
  }

  @override
  Future<void> fling(double dy, Duration over) =>
      _tester.timedDrag(host.viewport, Offset(0, dy), over, frequency: 120);

  @override
  Future<void> frames(int count) async {
    for (var i = 0; i < count; i++) {
      await _tester.pump();
    }
  }

  @override
  Future<int> framesUntilIdle({int cap = 240}) async {
    var n = 0;
    do {
      await _tester.pump();
      n++;
    } while (_tester.binding.hasScheduledFrame && n < cap);
    return n;
  }

  Future<void> _settle() async {
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    do {
      await _tester.pump(const Duration(milliseconds: 16));
    } while (_tester.binding.hasScheduledFrame &&
        DateTime.now().isBefore(deadline));
  }

  @override
  SelectionState get state {
    final s = host.selection;
    final range = s.textSelection;
    return SelectionState(
      selectedIds: {...s.selectedIds},
      isTextSelectionActive: s.isTextSelectionActive,
      textSelectionSubject: s.textSelectionSubject,
      extentChars: switch (range) {
        final r? => (r.extent.offset - r.base.offset).abs(),
        null => 0,
      },
    );
  }

  @override
  void clearSelection() => host.selection.clear();

  @override
  List<ChatSelectionInteraction> get interactions => host.interactions;

  @override
  Duration? get menuRequestLatency =>
      switch ((host.lastMenuRequestAt, host.lastPointerUpAt)) {
        (final request?, final up?) => request - up,
        _ => null,
      };

  @override
  bool get menuOpen => host.menuOpen;

  @override
  Future<void> dismissMenu() async {
    await tap(const Offset(4, 4));
    await framesUntilIdle();
  }

  @override
  Map<String, Metric> metricsOf(String window) =>
      windows[window] ?? (throw StateError('window "$window" not measured'));

  @override
  void report(String window, Map<String, Metric> metrics) =>
      metricsOf(window).addAll(metrics);
}
