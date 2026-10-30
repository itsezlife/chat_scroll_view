/// Tail data churn scenarios on the bench host (spec 7.2). Pure Dart: they
/// speak only to a [ChurnContext].
library;

import '../bench_setup.dart';
import '../churn.dart';
import '../metrics.dart';
import '../registry.dart';

/// Seated mid-history, as the "away" state of the spec.
const int _awayId = 10000;

Scenario _churn({
  required String id,
  required List<String> windows,
  required Future<void> Function(ChurnContext ctx) run,
  bool cold = false,
  bool deterministic = false,
  BenchSetup setup = const BenchSetup(),
}) => Scenario(
  id: id,
  version: 1,
  windows: windows,
  cold: cold,
  deterministic: deterministic,
  setup: setup,
  run: (ctx) => switch (ctx) {
    final ChurnContext c => run(c),
    _ => throw StateError('$id needs a churn-capable context'),
  },
);

/// One window of a frame-clocked schedule; the trace goes to [metrics].
Future<void> _scheduled(
  ChurnContext ctx,
  FrameSchedule schedule,
  Map<String, Metric> Function(List<ChurnFrame> frames) metrics, {
  Future<void> Function()? primer,
  int postRoll = kPostRollFrames,
}) => ctx.measure('churn', primer: primer, () async {
  final frames = await ctx.runSchedule(schedule, postRoll: postRoll);
  ctx.report('churn', metrics(frames));
});

/// One insert per frame on frames 0 to 19.
FrameSchedule _burst(ChurnHost host) {
  final schedule = FrameSchedule();
  for (var i = 0; i < 20; i++) {
    schedule.atFrame(i, () => host.insert(self: false));
  }
  return schedule;
}

Future<void> Function() _primeInsert(ChurnContext ctx, {required bool self}) =>
    () async => ctx.churn.insert(self: self);

final _sendAtTail = _churn(
  id: 'churn.send_at_tail',
  deterministic: true,
  windows: const ['churn'],
  run: (ctx) async {
    final host = ctx.churn;
    await ctx.seatTail();
    await _scheduled(
      ctx,
      FrameSchedule()..atFrame(0, () => host.insert(self: true)),
      (f) => {
        'tail.pin_frames': ChurnMetric.count(
          tailPinFrames(f) ?? f.length,
          headline: true,
        ),
        // Anchor changes in the still pre-roll.
        'jump.messages': ChurnMetric.count(
          anchorIdChanges([
            for (final x in f)
              if (x.index < 0) x,
          ]),
        ),
      },
      primer: _primeInsert(ctx, self: true),
    );
  },
);

final _sendAway = _churn(
  id: 'churn.send_away',
  deterministic: true,
  windows: const ['churn'],
  run: (ctx) async {
    final host = ctx.churn;
    await ctx.seat(_awayId);
    var newest = 0;
    await _scheduled(
      ctx,
      FrameSchedule()..atFrame(0, () {
        host.insert(self: true);
        newest = host.newestId;
      }),
      (f) => {
        'animate.travel_frames': ChurnMetric.count(
          tailPinFrames(f, newestId: newest) ?? f.length,
          headline: true,
        ),
        'final_anchor_is_newest': ChurnMetric.exactDp(
          f.last.anchorId == newest ? 1 : 0,
        ),
        'settle_ms': ChurnMetric.ms(settleMs(f)),
      },
      // The travel to the newest message outlasts the default post-roll.
      postRoll: 240,
    );
  },
);

final _incomingBurstTail = _churn(
  id: 'churn.incoming_burst_tail',
  deterministic: true,
  windows: const ['churn'],
  run: (ctx) async {
    await ctx.seatTail();
    await _scheduled(
      ctx,
      _burst(ctx.churn),
      (f) => {
        'tail.unpinned_frames': ChurnMetric.count(
          tailUnpinnedFrames(f),
          headline: true,
        ),
      },
      primer: _primeInsert(ctx, self: false),
    );
  },
);

final _incomingWhileAway = _churn(
  id: 'churn.incoming_while_away',
  deterministic: true,
  windows: const ['churn'],
  run: (ctx) async {
    await ctx.seat(_awayId);
    await _scheduled(
      ctx,
      _burst(ctx.churn),
      (f) => {
        'anchor.drift_dp': ChurnMetric.dp(anchorDriftDp(f), headline: true),
        'anchor.id_changes': ChurnMetric.count(anchorIdChanges(f)),
        'tail.unpinned_frames': ChurnMetric.count(tailUnpinnedFrames(f)),
      },
      primer: _primeInsert(ctx, self: false),
    );
  },
);

/// `motion=fling`: the burst under a fling, judged against a control fling
/// without the inserts. Both windows start from the same seat.
final _incomingWhileAwayFling = _churn(
  id: 'churn.incoming_while_away_fling',
  windows: const ['control', 'churn'],
  run: (ctx) async {
    final host = ctx.churn;
    Future<ChurnFrame> flung(String window, {ChurnFrame? control}) async {
      await ctx.seat(_awayId);
      late ChurnFrame end;
      await ctx.measure(window, () async {
        final frames = await ctx.recordFrames(() async {
          if (control != null) {
            // One insert per frame while the fling runs.
            final burst = _burst(host);
            var frame = 0;
            final inserting = Future(() async {
              while (frame < 20) {
                for (final a in burst.actionsAt(frame++)) {
                  a();
                }
                await Future<void>.delayed(const Duration(milliseconds: 8));
              }
            });
            await ctx.fling(400, const Duration(milliseconds: 150));
            await inserting;
          } else {
            await ctx.fling(400, const Duration(milliseconds: 150));
          }
          await ctx.settle();
        });
        end = frames.last;
        if (control != null) {
          ctx.report(window, {
            'anchor.drift_dp': ChurnMetric.dp(
              (end.anchorOffsetDp - control.anchorOffsetDp).abs(),
              headline: true,
            ),
            'anchor.id_changes': ChurnMetric.count(
              end.anchorId == control.anchorId ? 0 : 1,
            ),
          });
        }
      });
      return end;
    }

    final control = await flung('control');
    await flung('churn', control: control);
  },
);

Scenario _editVisible(String state) => _churn(
  id: 'churn.edit_visible_$state',
  deterministic: true,
  windows: const ['churn'],
  run: (ctx) async {
    final host = ctx.churn;
    if (state == 'away') {
      await ctx.seat(_awayId);
    } else {
      await ctx.seatTail();
    }
    int? id;
    await _scheduled(
      ctx,
      FrameSchedule()
        ..atFrame(0, () {
          id = host.visibleNonAnchorId;
          if (id case final i?) host.edit(i, taller: true);
        })
        ..atFrame(30, () {
          if (id case final i?) host.edit(i, taller: false);
        }),
      // The expected anchor behaviour for a height-changing edit is not
      // pinned, so the drift stays diagnostic.
      (f) => {
        'anchor.drift_dp': ChurnMetric.dp(anchorDriftDp(f)),
        'anchor.id_changes': ChurnMetric.count(anchorIdChanges(f)),
      },
    );
  },
);

final _deleteVisible = _churn(
  id: 'churn.delete_visible',
  deterministic: true,
  windows: const ['churn'],
  run: (ctx) async {
    final host = ctx.churn;
    await ctx.seat(_awayId);
    await _scheduled(
      ctx,
      FrameSchedule()..atFrame(0, () {
        if (host.visibleNonAnchorId case final id?) host.remove(id);
      }),
      (f) => {
        'band.bottom_shift_dp': ChurnMetric.dp(
          bandBottomShiftDp(f) ?? 0,
          headline: true,
        ),
        'settle_ms': ChurnMetric.ms(settleMs(f)),
      },
    );
  },
);

final _deleteAnchor = _churn(
  id: 'churn.delete_anchor',
  deterministic: true,
  windows: const ['churn'],
  run: (ctx) async {
    final host = ctx.churn;
    await ctx.seat(_awayId);
    await _scheduled(
      ctx,
      FrameSchedule()..atFrame(0, () => host.remove(_awayId)),
      (f) => {
        'band.bottom_shift_dp': ChurnMetric.dp(
          bandBottomShiftDp(f) ?? 0,
          headline: true,
        ),
      },
    );
  },
);

/// `tall`: the anchor is the designated tall message.
final _deleteAnchorTall = _churn(
  id: 'churn.delete_anchor_tall',
  deterministic: true,
  windows: const ['churn'],
  run: (ctx) async {
    final host = ctx.churn;
    // Aligned to the top, so the tall body fills the viewport.
    await ctx.seat(kTallMessageId, alignment: 0);
    await _scheduled(
      ctx,
      FrameSchedule()..atFrame(0, () => host.remove(kTallMessageId)),
      (f) => {
        'band.bottom_shift_dp': ChurnMetric.dp(bandBottomShiftDp(f) ?? 0),
        'scroll.delta_dp': ChurnMetric.exactDp(finalScrollDeltaDp(f)),
      },
    );
  },
);

final _chunkLoadUp = _churn(
  id: 'churn.chunk_load_up',
  windows: const ['drag'],
  setup: const BenchSetup(latency: BenchLatency.network, lazy: true),
  run: (ctx) async {
    await ctx.seat(_awayId);
    await ctx.measure('drag', () async {
      final frames = await ctx.recordFrames(() async {
        for (var i = 0; i < 8; i++) {
          await ctx.drag(2000, const Duration(seconds: 1));
        }
      });
      final runs = placeholderRunsMs(frames);
      ctx.report('drag', {
        'chunk.shimmer_frames': ChurnMetric.count(
          shimmerFrames(frames),
          headline: true,
        ),
        'chunk.first_paint_ms': ChurnMetric.ms(
          runs.isEmpty ? 0 : runs.reduce((a, b) => a > b ? a : b),
          headline: true,
        ),
        'chunk.crossings': ChurnMetric.count(runs.length),
        'chunk.anchor_travel_ids': ChurnMetric.count(
          (frames.first.anchorId - frames.last.anchorId).abs(),
        ),
      });
    });
  },
);

final _unreadBoundary = _churn(
  id: 'churn.unread_boundary',
  deterministic: true,
  windows: const ['churn'],
  run: (ctx) async {
    final host = ctx.churn;
    await ctx.seat(_awayId);
    final other = host.visibleNonAnchorId ?? _awayId - 1;
    await _scheduled(
      ctx,
      FrameSchedule()
        ..atFrame(0, () => host.setUnreadBoundary(_awayId))
        ..atFrame(20, () => host.setUnreadBoundary(other))
        ..atFrame(40, () => host.setUnreadBoundary(null)),
      (f) => {
        'anchor.drift_dp': ChurnMetric.dp(anchorDriftDp(f)),
        'anchor.id_changes': ChurnMetric.count(anchorIdChanges(f)),
      },
    );
  },
);

final _firstOpen = _churn(
  id: 'churn.first_open',
  windows: const ['first_open'],
  cold: true,
  run: (ctx) => ctx.measure('first_open', () async {
    await ctx.settle();
    ctx.report('first_open', {
      // Mount to the first message built; not raster.
      'first_paint_ms': ChurnMetric.ms(
        ctx.churn.firstBuildMs ?? double.nan,
        headline: true,
      ),
    });
  }),
);

/// The churn family.
final churnScenarios = ScenarioRegistry([
  _sendAtTail,
  _sendAway,
  _incomingBurstTail,
  _incomingWhileAway,
  _incomingWhileAwayFling,
  _editVisible('tail'),
  _editVisible('away'),
  _deleteVisible,
  _deleteAnchor,
  _deleteAnchorTall,
  _chunkLoadUp,
  _unreadBoundary,
  _firstOpen,
]);
