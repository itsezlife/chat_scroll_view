/// Navigation scenarios on the bench host (spec 7.1): jumps and animations
/// near and far, jump to the newest, the date pill during a fling.
library;

import '../registry.dart';
import 'script_support.dart';

const _repeats = 4;

/// `nav.jump_near` / `nav.jump_far`: `jumpTo` a message [distance] away and
/// back, [_repeats] times. Reports frames to land and the final anchor.
Scenario _jump(String name, int distance) => Scenario(
  id: 'nav.$name',
  version: 1,
  windows: const ['jump'],
  deterministic: true,
  run: (ctx) async {
    final mid = midHistory(ctx);
    final far = (mid + distance).clamp(0, ctx.history - 1);
    await ctx.jumpTo(mid);
    var landFrames = 0;
    await ctx.measure('jump', primer: seatedPrimer(ctx), () async {
      for (var i = 0; i < _repeats; i++) {
        final frames = await ctx.jumpTo(i.isEven ? far : mid);
        if (frames > landFrames) landFrames = frames;
        await ctx.idle(const Duration(milliseconds: 200));
      }
    });
    ctx.record('jump', 'land_frames_max', count(landFrames));
    ctx.record('jump', 'anchor_id', exact(ctx.anchorId));
  },
);

/// `nav.animate_near` / `nav.animate_far`: `animateTo` the same targets.
/// Reports the travel frames and the exact final anchor.
Scenario _animate(String name, int distance, Duration duration) => Scenario(
  id: 'nav.$name',
  version: 1,
  windows: const ['animate'],
  deterministic: true,
  run: (ctx) async {
    final mid = midHistory(ctx);
    final far = (mid + distance).clamp(0, ctx.history - 1);
    await ctx.jumpTo(mid);
    var travel = 0;
    var anchorId = mid;
    var anchorOffset = 0.0;
    await ctx.measure('animate', primer: seatedPrimer(ctx), () async {
      for (var i = 0; i < _repeats; i++) {
        final end = await ctx.animateTo(i.isEven ? far : mid, duration);
        if (end.frames > travel) travel = end.frames;
        anchorId = end.anchorId;
        anchorOffset = end.anchorOffset;
        await ctx.idle(const Duration(milliseconds: 200));
      }
    });
    ctx.record('animate', 'travel_frames_max', count(travel));
    ctx.record('animate', 'anchor_id', exact(anchorId));
    ctx.record('animate', 'anchor_offset_dp', exact(anchorOffset));
  },
);

/// `nav.jump_to_newest`: from mid-history to the tail.
final _jumpToNewest = Scenario(
  id: 'nav.jump_to_newest',
  version: 1,
  windows: const ['jump_to_newest'],
  deterministic: true,
  run: (ctx) async {
    await ctx.jumpTo(midHistory(ctx));
    var pin = 0;
    await ctx.measure('jump_to_newest', primer: seatedPrimer(ctx), () async {
      pin = await ctx.jumpToNewest();
    });
    ctx.record('jump_to_newest', 'tail.pin_frames', count(pin));
    ctx.record('jump_to_newest', 'anchor_id', exact(ctx.anchorId));
  },
);

/// `nav.date_pill_during_fling`: a fling with the floating date header shown.
final _datePillDuringFling = Scenario(
  id: 'nav.date_pill_during_fling',
  version: 1,
  windows: const ['fling'],
  deterministic: true,
  floatingDayHeader: true,
  run: (ctx) async {
    await ctx.jumpTo(midHistory(ctx));
    var result = (messages: 0, settle: Duration.zero);
    await ctx.measure('fling', primer: seatedPrimer(ctx), () async {
      result = await flingTrial(ctx, -600, const Duration(milliseconds: 90));
    });
    ctx.record('fling', 'fling.messages', exact(result.messages));
    ctx.record('fling', 'settle_ms', ms(result.settle.inMilliseconds));
  },
);

/// The navigation family.
final navScenarios = <Scenario>[
  _jump('jump_near', 20),
  _jump('jump_far', 5000),
  _animate('animate_near', 20, const Duration(milliseconds: 300)),
  _animate('animate_far', 5000, const Duration(milliseconds: 800)),
  _jumpToNewest,
  _datePillDuringFling,
];
