import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/chat_perf/gesture_driver.dart';
import '../../integration_test/chat_perf/metrics.dart';
import '../../integration_test/chat_perf/registry.dart';
import '../../integration_test/chat_perf/scenarios/scroll_scenarios.dart';

final class _RecordingContext implements ScenarioContext {
  final calls = <String>[];
  double totalDragDp = 0;
  Duration totalDrag = Duration.zero;
  String? open;
  bool primed = false;

  @override
  Future<void> measure(
    String name,
    Future<void> Function() body, {
    Future<void> Function()? primer,
  }) async {
    if (primer case final p?) {
      primed = true;
      await p();
    } else {
      primed = false;
    }
    calls.add('begin $name');
    open = name;
    await body();
    open = null;
    calls.add('end $name');
  }

  @override
  Future<void> drag(double dy, Duration duration) async {
    switch (open) {
      case null:
        calls.add('drag outside');
      case _:
        calls.add('drag inside');
        totalDragDp += dy.abs();
        totalDrag += duration;
    }
  }

  @override
  Future<void> settle() async => calls.add('settle');

  int _anchor = 5000;
  final recorded = <String, Metric>{};
  final flings = <(double, Duration)>[];

  @override
  int get history => 10000;

  @override
  int get anchorId => _anchor;

  @override
  Future<({Duration time, int frames})> settleTimed() async {
    calls.add('settle');
    return (time: const Duration(milliseconds: 900), frames: 5);
  }

  @override
  Future<void> fling(double dy, Duration duration) async {
    flings.add((dy, duration));
    calls.add('fling');
    _anchor += dy < 0 ? 51 : -50;
  }

  @override
  Future<void> touch(Duration hold) async => calls.add('touch');

  @override
  Future<void> idle(Duration duration) async => calls.add('idle');

  @override
  Future<int> jumpTo(int id) async {
    calls.add('jumpTo $id');
    _anchor = id;
    return 3;
  }

  @override
  Future<({int frames, int anchorId, double anchorOffset})> animateTo(
    int id,
    Duration duration,
  ) async {
    _anchor = id;
    return (frames: 20, anchorId: id, anchorOffset: 0.0);
  }

  @override
  Future<int> jumpToNewest() async => jumpTo(history - 1);

  @override
  Future<void> scrollbarDrag(double dy, Duration duration) async =>
      calls.add('scrollbarDrag');

  @override
  Future<List<int>> anchorSteps(Future<void> Function() body) async {
    await body();
    return [0, 30, 35, 400, 32];
  }

  @override
  void record(String window, String name, Metric metric) =>
      recorded['$window/$name'] = metric;

  @override
  GestureDriver get gestures => throw UnimplementedError();
}

void main() {
  Scenario slow() =>
      scrollScenarios.all.singleWhere((s) => s.id == 'scroll.drag_slow');

  test('scroll.drag_slow is registered with its declared window', () {
    expect(slow().key, 'scroll.drag_slow@2');
    expect(slow().windows, ['drag']);
  });

  test(
    'only declared windows are measured; slow drags last about 8 s',
    () async {
      final ctx = _RecordingContext();
      await slow().run(ctx);
      final windows = [
        for (final c in ctx.calls)
          if (c.startsWith('begin ')) c.substring(6),
      ];
      expect(windows, slow().windows);
      // The primer is a drag outside the window, handed to measure.
      expect(ctx.primed, isTrue);
      expect(ctx.calls.first, 'drag outside');
      expect(ctx.totalDrag.inMilliseconds, inInclusiveRange(7500, 8500));
      // About 400 dp per 1.5 s.
      expect(
        ctx.totalDragDp / (ctx.totalDrag.inMilliseconds / 1000),
        closeTo(400 / 1.5, 1),
      );
    },
  );

  test('scroll.first_scroll is a cold scenario without a primer', () async {
    final s = scrollScenarios.all.singleWhere(
      (s) => s.id == 'scroll.first_scroll',
    );
    expect(s.cold, isTrue);
    expect(s.windows, ['first_scroll']);
    final ctx = _RecordingContext();
    await s.run(ctx);
    expect(ctx.primed, isFalse);
    expect(ctx.calls.first, 'begin first_scroll');
  });

  group('scrollbar drag', () {
    test('a jump is a step far above the drag\'s own rate', () {
      final m = anchorStepMetrics([0, 30, 35, 400, 32, 0, 36]);
      expect(m['median_step_messages']!.value, 35);
      expect(m['max_step_messages']!.value, 400);
      expect(m['jump_frames']!.value, 1);
    });

    test('a steady drag of tens of ids a frame has no jump', () {
      final m = anchorStepMetrics([for (var i = 0; i < 40; i++) 35]);
      expect(m['jump_frames']!.value, 0);
      expect(m['max_step_messages']!.value, 35);
    });

    test('a drag that never moves reports zeros', () {
      final m = anchorStepMetrics([0, 0, 0]);
      expect(m.values.map((v) => v.value), [0, 0, 0]);
    });

    test('the scenario records the step metrics', () async {
      final ctx = _RecordingContext();
      await scrollScenarios.all
          .singleWhere((s) => s.id == 'scroll.scrollbar_drag')
          .run(ctx);
      expect(ctx.recorded['scrollbar/jump_frames']!.value, 1);
      expect(ctx.recorded['scrollbar/max_step_messages']!.value, 400);
    });
  });

  group('the family', () {
    const expected = [
      'scroll.drag_slow',
      'scroll.drag_fast',
      'scroll.fling_single',
      'scroll.fling_burst',
      'scroll.fling_reverse',
      'scroll.stop_on_touch',
      'scroll.overscroll_oldest',
      'scroll.scrollbar_drag',
      'scroll.first_scroll',
      'nav.jump_near',
      'nav.jump_far',
      'nav.animate_near',
      'nav.animate_far',
      'nav.jump_to_newest',
      'nav.date_pill_during_fling',
      'scroll.real.drag_slow',
      'scroll.real.fling_single',
      'scroll.real.fling_burst',
    ];

    test('registers every scenario of the ticket', () {
      expect(scrollScenarios.all.map((s) => s.id), containsAll(expected));
    });

    test('every scenario runs and records into windows it declared', () async {
      for (final s in scrollScenarios.all) {
        final ctx = _RecordingContext();
        await s.run(ctx);
        for (final key in ctx.recorded.keys) {
          expect(s.windows, contains(key.split('/').first), reason: s.id);
        }
      }
    });

    test('real-screen variants run on the real chat screen', () {
      final real = scrollScenarios.all.where((s) => s.id.contains('.real.'));
      expect(real.map((s) => s.id), [
        'scroll.real.drag_slow',
        'scroll.real.fling_single',
        'scroll.real.fling_burst',
      ]);
      for (final s in real) {
        expect(s.subject, ScenarioSubject.realChat);
      }
      expect(
        scrollScenarios.all
            .where((s) => !s.id.contains('.real.'))
            .every((s) => s.subject == ScenarioSubject.bench),
        isTrue,
      );
    });

    test('deterministic flags: first_scroll is cold, the rest of D set', () {
      Scenario by(String id) =>
          scrollScenarios.all.singleWhere((s) => s.id == id);
      expect(by('scroll.fling_burst').deterministic, isTrue);
      expect(by('nav.jump_to_newest').deterministic, isTrue);
      expect(by('scroll.first_scroll').deterministic, isFalse);
      expect(by('scroll.real.fling_burst').deterministic, isFalse);
    });

    test('the date pill scenario mounts the floating header', () {
      final s = scrollScenarios.all.singleWhere(
        (s) => s.id == 'nav.date_pill_during_fling',
      );
      expect(s.floatingDayHeader, isTrue);
    });

    test('the ladder reports exact distance per rung and settle_ms', () async {
      final s = scrollScenarios.all.singleWhere(
        (s) => s.id == 'scroll.fling_burst',
      );
      final ctx = _RecordingContext();
      await s.run(ctx);
      expect(s.windows, ['fling_2k', 'fling_6k', 'fling_13k']);
      for (final w in s.windows) {
        final up = ctx.recorded['$w/fling.finger_up_messages']!;
        expect(up.kind, MetricKind.exact);
        expect(
          ctx.recorded['$w/fling.finger_down_messages']!.kind,
          MetricKind.exact,
        );
        expect(ctx.recorded['$w/settle_ms']!.value, 900);
      }
      // Three repetitions each direction, six trials a rung, three rungs.
      expect(ctx.flings.length, 18);
    });

    test('nav.jump_to_newest reports tail.pin_frames', () async {
      final s = scrollScenarios.all.singleWhere(
        (s) => s.id == 'nav.jump_to_newest',
      );
      final ctx = _RecordingContext();
      await s.run(ctx);
      expect(ctx.recorded['jump_to_newest/tail.pin_frames']!.value, 3);
    });

    test(
      'animate scenarios report travel frames and an exact anchor',
      () async {
        final s = scrollScenarios.all.singleWhere(
          (s) => s.id == 'nav.animate_far',
        );
        final ctx = _RecordingContext();
        await s.run(ctx);
        expect(ctx.recorded['animate/travel_frames_max']!.value, 20);
        expect(ctx.recorded['animate/anchor_id']!.kind, MetricKind.exact);
      },
    );

    test('flings are paced streams: every fling has a duration', () async {
      for (final s in scrollScenarios.all) {
        final ctx = _RecordingContext();
        await s.run(ctx);
        for (final (_, d) in ctx.flings) {
          expect(d, greaterThan(Duration.zero), reason: s.id);
        }
      }
    });
  });
}
