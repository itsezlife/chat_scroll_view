import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/chat_perf/bench_setup.dart';
import '../../integration_test/chat_perf/churn.dart';
import '../../integration_test/chat_perf/corpus.dart';
import '../../integration_test/chat_perf/metrics.dart';
import '../../integration_test/chat_perf/registry.dart';
import '../../integration_test/chat_perf/scenarios/churn_scenarios.dart';

ChurnFrame _f(
  int i, {
  int anchor = 5,
  double offset = 100,
  bool tail = true,
  double? band = 800,
  int placeholders = 0,
}) => ChurnFrame(
  index: i,
  tMs: i * 8.0 + 100,
  anchorId: anchor,
  anchorOffsetDp: offset,
  isAtTail: tail,
  bandBottomDp: band,
  placeholders: placeholders,
);

final class _FakeHost implements ChurnHost {
  final log = <String>[];
  @override
  int newestId = 10;
  @override
  int? visibleNonAnchorId = 3;
  @override
  double? firstBuildMs = 42;
  @override
  void insert({required bool self}) => log.add('insert self=$self');
  @override
  void edit(int id, {required bool taller}) =>
      log.add('edit $id taller=$taller');
  @override
  void remove(int id) => log.add('remove $id');
  @override
  void setUnreadBoundary(int? id) => log.add('unread $id');
}

/// Runs schedules by firing each action at its frame, with a canned trace.
final class _FakeContext extends Fake implements ChurnContext {
  @override
  final _FakeHost churn = _FakeHost();
  final reports = <String, Map<String, Metric>>{};
  final windows = <String>[];
  bool primed = false;

  @override
  void report(String name, Map<String, Metric> metrics) =>
      (reports[name] ??= {}).addAll(metrics);

  @override
  Future<void> measure(
    String name,
    Future<void> Function() body, {
    Future<void> Function()? primer,
  }) async {
    if (primer != null) {
      primed = true;
      await primer();
    }
    windows.add(name);
    await body();
  }

  @override
  Future<List<ChurnFrame>> runSchedule(
    FrameSchedule schedule, {
    int preRoll = kPreRollFrames,
    int postRoll = kPostRollFrames,
  }) async {
    final frames = <ChurnFrame>[];
    for (var f = -preRoll; f <= schedule.lastFrame + postRoll; f++) {
      if (f >= 0) {
        for (final a in schedule.actionsAt(f)) {
          a();
        }
      }
      frames.add(_f(f, anchor: churn.newestId));
    }
    return frames;
  }

  @override
  Future<List<ChurnFrame>> recordFrames(Future<void> Function() body) async {
    await body();
    return [_f(0), _f(1)];
  }

  @override
  Future<void> seatTail() async => churn.log.add('seat tail');

  @override
  Future<void> seatOn(int id, {double alignment = 0.5}) async =>
      churn.log.add('seat $id');

  @override
  Future<void> fling(double dy, Duration duration) async =>
      churn.log.add('fling');

  @override
  Future<void> drag(double dy, Duration duration) async =>
      churn.log.add('drag');

  @override
  Future<void> settle() async {}
}

void main() {
  group('FrameSchedule', () {
    test('fires actions at their frame in order', () {
      final order = <String>[];
      final s = FrameSchedule()
        ..atFrame(2, () => order.add('b'))
        ..atFrame(0, () => order.add('a'))
        ..atFrame(2, () => order.add('c'));
      expect(s.lastFrame, 2);
      expect(s.actionsAt(1), isEmpty);
      for (final a in s.actionsAt(2)) {
        a();
      }
      expect(order, ['b', 'c']);
    });
  });

  group('outcome metrics', () {
    test('tailPinFrames counts to the first pinned post frame', () {
      final frames = [
        _f(-1),
        _f(0, tail: false, anchor: 5),
        _f(1, tail: false, anchor: 5),
        _f(2, anchor: 11),
      ];
      expect(tailPinFrames(frames), 3);
      expect(tailPinFrames(frames, newestId: 11), 3);
      expect(tailPinFrames(frames, newestId: 99), isNull);
      expect(tailPinFrames([_f(-1), _f(0)]), 1);
    });

    test('tailUnpinnedFrames counts post frames off the tail', () {
      final frames = [
        _f(-1, tail: false),
        _f(0),
        _f(1, tail: false),
        _f(2, tail: false),
      ];
      expect(tailUnpinnedFrames(frames), 2);
    });

    test('anchorDriftDp is exactly zero for a still anchor', () {
      expect(anchorDriftDp([for (var i = -2; i < 5; i++) _f(i)]), 0);
    });

    test('anchorDriftDp ignores frames of another anchor', () {
      final frames = [
        _f(-1),
        _f(0, offset: 103),
        _f(1, anchor: 6, offset: 900),
      ];
      expect(anchorDriftDp(frames), 3);
      expect(anchorIdChanges(frames), 1);
    });

    test('bandBottomShiftDp is null without a baseline band', () {
      expect(bandBottomShiftDp([_f(-1, band: null), _f(0)]), isNull);
      expect(
        bandBottomShiftDp([_f(-1), _f(0, band: 805), _f(1, band: 794)]),
        6,
      );
    });

    test('finalScrollDeltaDp is exact zero when nothing moved', () {
      expect(finalScrollDeltaDp([_f(-1), _f(0), _f(1)]), 0);
    });

    test('settleMs is the time of the last movement from frame 0', () {
      final frames = [
        _f(-1),
        _f(0),
        _f(1, offset: 110),
        _f(2, offset: 120),
        _f(3, offset: 120),
      ];
      expect(settleMs(frames), 16);
    });

    test('placeholder runs measure each boundary crossing', () {
      final frames = [
        _f(0),
        _f(1, placeholders: 2),
        _f(2, placeholders: 1),
        _f(3),
        _f(4, placeholders: 1),
        _f(5),
      ];
      expect(shimmerFrames(frames), 3);
      expect(placeholderRunsMs(frames), [16, 8]);
    });
  });

  group('corpus', () {
    test('the tall message is fixed and at least 140 lines in any history', () {
      for (final count in [20000, 12001]) {
        final text = BenchCorpus(count: count).messageAt(kTallMessageId).text;
        expect(text.split('\n'), hasLength(140));
      }
    });

    test('the network profile is seeded: same range, same delay', () {
      final a = BenchLatency.network.delayFor(640);
      expect(BenchLatency.network.delayFor(640), a);
      expect(a, greaterThanOrEqualTo(const Duration(milliseconds: 60)));
      expect(a, lessThan(const Duration(milliseconds: 180)));
      final delays = {
        for (var i = 0; i < 50; i++) BenchLatency.network.delayFor(i * 64),
      };
      expect(delays.length, greaterThan(10));
      expect(BenchLatency.instant.delayFor(640), Duration.zero);
    });

    test('an edit moves updatedAt', () {
      final m = const BenchCorpus(count: 10).messageAt(2);
      expect(m.edited('x').updatedAt.isAfter(m.updatedAt), isTrue);
    });
  });

  group('churn scenarios', () {
    Scenario byId(String id) =>
        churnScenarios.all.singleWhere((s) => s.id == id);

    test('the registry holds the ticket scenarios', () {
      expect(
        [for (final s in churnScenarios.all) s.id],
        containsAll([
          'churn.send_at_tail',
          'churn.send_away',
          'churn.incoming_burst_tail',
          'churn.incoming_while_away',
          'churn.incoming_while_away_fling',
          'churn.edit_visible_tail',
          'churn.edit_visible_away',
          'churn.delete_visible',
          'churn.delete_anchor',
          'churn.delete_anchor_tall',
          'churn.chunk_load_up',
          'churn.unread_boundary',
          'churn.first_open',
        ]),
      );
      expect(byId('churn.first_open').cold, isTrue);
      expect(byId('churn.chunk_load_up').setup.latency, BenchLatency.network);
    });

    test('send_at_tail inserts once and reports the pin frames', () async {
      final ctx = _FakeContext();
      await byId('churn.send_at_tail').run(ctx);
      expect(ctx.churn.log, [
        'seat tail',
        'insert self=true',
        'insert self=true',
      ]);
      expect(ctx.primed, isTrue);
      expect(ctx.reports['churn'], contains('tail.pin_frames'));
    });

    test('the burst inserts one message per frame for 20 frames', () async {
      final ctx = _FakeContext();
      await byId('churn.incoming_burst_tail').run(ctx);
      // One primer insert, then twenty.
      expect(ctx.churn.log.where((e) => e.startsWith('insert')), hasLength(21));
      expect(ctx.reports['churn']!['tail.unpinned_frames']!.value, 0);
    });

    test('delete_anchor_tall removes the designated tall message', () async {
      final ctx = _FakeContext();
      await byId('churn.delete_anchor_tall').run(ctx);
      expect(ctx.churn.log, ['seat $kTallMessageId', 'remove $kTallMessageId']);
      expect(ctx.reports['churn'], contains('scroll.delta_dp'));
    });

    test('edit_visible makes the body taller, then restores it', () async {
      final ctx = _FakeContext();
      await byId('churn.edit_visible_tail').run(ctx);
      expect(ctx.churn.log, [
        'seat tail',
        'edit 3 taller=true',
        'edit 3 taller=false',
      ]);
      expect(
        ctx.reports['churn']!['anchor.drift_dp']!.role,
        MetricRole.diagnostic,
      );
    });

    test('unread_boundary moves the boundary, then clears it', () async {
      final ctx = _FakeContext();
      await byId('churn.unread_boundary').run(ctx);
      expect(ctx.churn.log.where((e) => e.startsWith('unread')), [
        'unread 10000',
        'unread 3',
        'unread null',
      ]);
    });

    test(
      'the fling variant measures a control window and a churn one',
      () async {
        final ctx = _FakeContext();
        await byId('churn.incoming_while_away_fling').run(ctx);
        expect(ctx.windows, ['control', 'churn']);
        expect(
          ctx.churn.log.where((e) => e == 'insert self=false'),
          hasLength(20),
        );
        expect(ctx.reports['churn'], contains('anchor.drift_dp'));
      },
    );

    test('first_open reports the first build time', () async {
      final ctx = _FakeContext();
      await byId('churn.first_open').run(ctx);
      expect(ctx.reports['first_open']!['first_paint_ms']!.value, 42);
    });
  });
}
