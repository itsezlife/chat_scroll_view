/// Scroll scenarios (spec 7.1) on the bench host, and three of them again on
/// the real chat screen as `scroll.real.*`. Pure Dart: they speak only to a
/// [ScenarioContext].
library;

import '../registry.dart';
import 'nav_scenarios.dart';
import 'scale_scenarios.dart';
import 'script_support.dart';

const _fling = Duration(milliseconds: 90);

/// The window of a script that drags: `scroll.drag_slow` and its real-screen
/// variant share it.
Scenario _dragSlow(String id, ScenarioSubject subject) => Scenario(
  id: id,
  version: 2,
  windows: const ['drag'],
  deterministic: subject == ScenarioSubject.bench,
  subject: subject,
  run: (ctx) => ctx.measure(
    'drag',
    primer: () => ctx.drag(60, const Duration(milliseconds: 500)),
    () => alternatingDrags(
      ctx,
      dp: 400,
      leg: const Duration(milliseconds: 1500),
      total: const Duration(seconds: 8),
    ),
  ),
);

/// `scroll.drag_fast`: about 600 dp per 0.6 s, alternating, 8 s.
final _dragFast = Scenario(
  id: 'scroll.drag_fast',
  version: 1,
  windows: const ['drag'],
  deterministic: true,
  run: (ctx) => ctx.measure(
    'drag',
    primer: () => ctx.drag(90, const Duration(milliseconds: 300)),
    () => alternatingDrags(
      ctx,
      dp: 600,
      leg: const Duration(milliseconds: 600),
      total: const Duration(seconds: 8),
    ),
  ),
);

/// `scroll.first_scroll` (cold): the first drag after mount, 3 s at the same
/// pace, with no primer. Its first frames are the headline.
final _firstScroll = Scenario(
  id: 'scroll.first_scroll',
  version: 1,
  windows: const ['first_scroll'],
  cold: true,
  run: (ctx) => ctx.measure(
    'first_scroll',
    () => alternatingDrags(
      ctx,
      dp: 400,
      leg: const Duration(milliseconds: 1500),
      total: const Duration(seconds: 3),
    ),
  ),
);

/// `scroll.fling_single`: one fling from mid-history at about 6.7k px/s.
Scenario _flingSingle(String id, ScenarioSubject subject) => Scenario(
  id: id,
  version: 1,
  windows: const ['fling'],
  deterministic: subject == ScenarioSubject.bench,
  subject: subject,
  run: (ctx) async {
    await ctx.jumpTo(midHistory(ctx));
    var result = (messages: 0, settle: Duration.zero);
    await ctx.measure('fling', primer: seatedPrimer(ctx), () async {
      result = await flingTrial(ctx, -600, _fling);
    });
    ctx.record('fling', 'fling.messages', exact(result.messages));
    ctx.record('fling', 'settle_ms', ms(result.settle.inMilliseconds));
  },
);

/// The ladder: finger travel and time give about 2k, 6.7k and 13k px/s.
const _rungs = <({String name, double dp, Duration duration})>[
  (name: 'fling_2k', dp: 400, duration: Duration(milliseconds: 200)),
  (name: 'fling_6k', dp: 600, duration: Duration(milliseconds: 90)),
  (name: 'fling_13k', dp: 800, duration: Duration(milliseconds: 60)),
];

/// `scroll.fling_burst`: the ladder, three repetitions each direction, seated
/// at mid-history before every trial. One window per rung.
Scenario _flingBurst(String id, ScenarioSubject subject) => Scenario(
  id: id,
  version: 1,
  windows: [for (final r in _rungs) r.name],
  deterministic: subject == ScenarioSubject.bench,
  subject: subject,
  run: (ctx) async {
    await ctx.jumpTo(midHistory(ctx));
    for (final rung in _rungs) {
      final byDirection = <double, List<FlingResult>>{-1: [], 1: []};
      await ctx.measure(rung.name, primer: seatedPrimer(ctx), () async {
        for (var rep = 0; rep < 3; rep++) {
          for (final sign in byDirection.keys) {
            byDirection[sign]!.add(
              await flingTrial(ctx, sign * rung.dp, rung.duration),
            );
          }
        }
      });
      var spread = 0;
      var settleMs = 0;
      var trials = 0;
      for (final results in byDirection.values) {
        final counts = [for (final r in results) r.messages];
        final s =
            counts.reduce((a, b) => a > b ? a : b) -
            counts.reduce((a, b) => a < b ? a : b);
        if (s > spread) spread = s;
        for (final r in results) {
          settleMs += r.settle.inMilliseconds;
          trials++;
        }
      }
      ctx.record(
        rung.name,
        'fling.finger_up_messages',
        exact(byDirection[-1]!.first.messages),
      );
      ctx.record(
        rung.name,
        'fling.finger_down_messages',
        exact(byDirection[1]!.first.messages),
      );
      ctx.record(rung.name, 'fling.rep_spread_messages', count(spread));
      ctx.record(rung.name, 'settle_ms', ms(settleMs / trials));
    }
  },
);

/// `scroll.fling_reverse`: a fling, then a counter-drag mid-fling.
final _flingReverse = Scenario(
  id: 'scroll.fling_reverse',
  version: 1,
  windows: const ['fling_reverse'],
  deterministic: true,
  run: (ctx) async {
    await ctx.jumpTo(midHistory(ctx));
    var settle = Duration.zero;
    await ctx.measure('fling_reverse', primer: seatedPrimer(ctx), () async {
      await ctx.fling(-600, _fling);
      await ctx.idle(const Duration(milliseconds: 300));
      await ctx.drag(300, const Duration(milliseconds: 250));
      settle = (await ctx.settleTimed()).time;
    });
    ctx.record('fling_reverse', 'settle_ms', ms(settle.inMilliseconds));
  },
);

/// `scroll.stop_on_touch`: a fling, then a touch down at +300 ms. Residual
/// travel after the touch is a diagnostic.
final _stopOnTouch = Scenario(
  id: 'scroll.stop_on_touch',
  version: 1,
  windows: const ['stop_on_touch'],
  deterministic: true,
  run: (ctx) async {
    await ctx.jumpTo(midHistory(ctx));
    var residual = 0;
    await ctx.measure('stop_on_touch', primer: seatedPrimer(ctx), () async {
      await ctx.fling(-600, _fling);
      await ctx.idle(const Duration(milliseconds: 300));
      final atTouch = ctx.anchorId;
      await ctx.touch(const Duration(milliseconds: 100));
      await ctx.settle();
      residual = ctx.anchorId - atTouch;
    });
    ctx.record('stop_on_touch', 'residual_messages', count(residual));
  },
);

/// `scroll.overscroll_oldest`: seat at the oldest message, drag past the edge,
/// release; the frames until the edge effect has returned.
final _overscrollOldest = Scenario(
  id: 'scroll.overscroll_oldest',
  version: 1,
  windows: const ['overscroll'],
  deterministic: true,
  run: (ctx) async {
    await ctx.jumpTo(0);
    var returnFrames = 0;
    await ctx.measure(
      'overscroll',
      primer: () async {
        await ctx.drag(60, const Duration(milliseconds: 300));
        await ctx.jumpTo(0);
      },
      () async {
        await ctx.drag(300, const Duration(milliseconds: 500));
        returnFrames = (await ctx.settleTimed()).frames;
      },
    );
    ctx.record('overscroll', 'edge_return_frames', count(returnFrames));
    ctx.record('overscroll', 'anchor_id', exact(ctx.anchorId));
  },
);

/// `scroll.scrollbar_drag`: grab the thumb and drag across the history.
final _scrollbarDrag = Scenario(
  id: 'scroll.scrollbar_drag',
  version: 1,
  windows: const ['scrollbar'],
  deterministic: true,
  run: (ctx) async {
    await ctx.jumpTo(midHistory(ctx));
    var jumps = 0;
    var moved = 0;
    await ctx.measure('scrollbar', primer: seatedPrimer(ctx), () async {
      final before = ctx.anchorId;
      jumps = await ctx.countAnchorJumps(
        () => ctx.scrollbarDrag(250, const Duration(milliseconds: 1500)),
      );
      await ctx.settle();
      moved = (ctx.anchorId - before).abs();
    });
    ctx.record('scrollbar', 'jump_count', count(jumps));
    ctx.record('scrollbar', 'moved_messages', count(moved));
  },
);

/// The scroll and navigation family, then the real-screen variants.
final scrollScenarios = ScenarioRegistry([
  _dragSlow('scroll.drag_slow', ScenarioSubject.bench),
  _dragFast,
  _flingSingle('scroll.fling_single', ScenarioSubject.bench),
  _flingBurst('scroll.fling_burst', ScenarioSubject.bench),
  _flingReverse,
  _stopOnTouch,
  _overscrollOldest,
  _scrollbarDrag,
  _firstScroll,
  ...navScenarios,
  ...scaleScenarios,
  _dragSlow('scroll.real.drag_slow', ScenarioSubject.realChat),
  _flingSingle('scroll.real.fling_single', ScenarioSubject.realChat),
  _flingBurst('scroll.real.fling_burst', ScenarioSubject.realChat),
]);
