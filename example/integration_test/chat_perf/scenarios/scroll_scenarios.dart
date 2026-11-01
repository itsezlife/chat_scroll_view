/// Scroll scenarios (spec 7.1) on the bench host, and three of them again on
/// the real chat screen as `scroll.real.*`. Pure Dart: they speak only to a
/// [ScenarioContext].
library;

import '../metrics.dart';
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
  run: (ctx) => ctx.measure('first_scroll', () => _firstScrollDrags(ctx)),
);

/// The first-scroll drag script, also run warm by [_firstScrollWarmed].
Future<void> _firstScrollDrags(ScenarioContext ctx) => alternatingDrags(
  ctx,
  dp: 400,
  leg: const Duration(milliseconds: 1500),
  total: const Duration(seconds: 3),
);

/// Idle before a warmed first-scroll window: long enough for clocks that ramp
/// up under load to fall back (under the system governors; fixed performance
/// mode pins them).
const _clockDecay = Duration(seconds: 3);

/// `scroll.first_scroll_warmed` (cold): separates the first-scroll penalty's
/// causes (finding 05). Outside any window, the same drags at mid-history
/// warm the raster pipelines and caches on other rows, then the viewport
/// returns to the tail and idles for [_clockDecay]. `after_warmup` is the
/// first-scroll drag on rows the launch has not scrolled; after another idle,
/// `repeat` is the same drag once more. A penalty that survives the warm-up
/// is not pipeline warm-up; one that comes back after the idle is the clock.
final _firstScrollWarmed = Scenario(
  id: 'scroll.first_scroll_warmed',
  version: 1,
  windows: const ['after_warmup', 'repeat'],
  cold: true,
  run: (ctx) async {
    await ctx.jumpTo(midHistory(ctx));
    await _firstScrollDrags(ctx);
    await ctx.jumpToNewest();
    await ctx.idle(_clockDecay);
    await ctx.measure('after_warmup', () => _firstScrollDrags(ctx));
    await ctx.idle(_clockDecay);
    await ctx.measure('repeat', () => _firstScrollDrags(ctx));
  },
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

/// How many times the median per-frame step a frame's step must exceed to
/// count as a discontinuous jump.
const kJumpStepFactor = 4;

/// The anchor's motion over a drag from its per-frame [steps] (ids moved
/// each frame): the median and the largest step, and `jump_frames`, the
/// frames whose step exceeds [kJumpStepFactor] times the median moving step.
///
/// The threshold is relative to the drag's own rate: a thumb drag moves tens
/// of ids a frame, so a fixed threshold either counts every frame or none.
/// A drag that never moves has no rate and no jump.
Map<String, Metric> anchorStepMetrics(List<int> steps) {
  final moving = [
    for (final s in steps)
      if (s > 0) s,
  ]..sort();
  final median = moving.isEmpty ? 0 : moving[moving.length ~/ 2];
  return {
    'median_step_messages': count(median),
    'max_step_messages': count(moving.isEmpty ? 0 : moving.last),
    'jump_frames': count(
      moving.where((s) => s > median * kJumpStepFactor).length,
    ),
  };
}

/// `scroll.scrollbar_drag`: grab the thumb and drag across the history.
///
/// Version 2: `jump_count` (frames moving more than 200 ids, which a thumb
/// drag at about 35 ids a frame never reaches) became [anchorStepMetrics].
final _scrollbarDrag = Scenario(
  id: 'scroll.scrollbar_drag',
  version: 2,
  windows: const ['scrollbar'],
  deterministic: true,
  run: (ctx) async {
    await ctx.jumpTo(midHistory(ctx));
    var steps = const <int>[];
    var moved = 0;
    await ctx.measure('scrollbar', primer: seatedPrimer(ctx), () async {
      final before = ctx.anchorId;
      steps = await ctx.anchorSteps(
        () => ctx.scrollbarDrag(250, const Duration(milliseconds: 1500)),
      );
      await ctx.settle();
      moved = (ctx.anchorId - before).abs();
    });
    for (final MapEntry(:key, :value) in anchorStepMetrics(steps).entries) {
      ctx.record('scrollbar', key, value);
    }
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
  _firstScrollWarmed,
  ...navScenarios,
  ...scaleScenarios,
  _dragSlow('scroll.real.drag_slow', ScenarioSubject.realChat),
  _flingSingle('scroll.real.fling_single', ScenarioSubject.realChat),
  _flingBurst('scroll.real.fling_burst', ScenarioSubject.realChat),
]);
