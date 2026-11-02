/// Scale scenarios (spec 7.5) on the bench host: the same few scripts at 1k,
/// 20k and 200k messages, reported as ratios against the 1k run. The far
/// scripts travel the whole history, so the distance grows with the tier.
library;

import '../registry.dart';
import '../scale.dart';
import 'script_support.dart';

const _repeats = 4;

/// `scale.fling`: one 6.7k px/s fling from mid-history.
final _fling = Scenario(
  id: 'scale.fling',
  version: 1,
  windows: const ['fling'],
  historyTiers: kScaleTiers,
  run: (ctx) async {
    await ctx.jumpTo(midHistory(ctx));
    var result = (messages: 0, settle: Duration.zero);
    await ctx.measure('fling', primer: seatedPrimer(ctx), () async {
      result = await flingTrial(ctx, -600, const Duration(milliseconds: 90));
    });
    ctx.record('fling', 'fling.messages', count(result.messages));
    ctx.record('fling', 'settle_ms', ms(result.settle.inMilliseconds));
  },
);

/// `scale.jump_far`: `jumpTo` the oldest and newest message alternately.
final _jumpFar = Scenario(
  id: 'scale.jump_far',
  version: 1,
  windows: const ['jump'],
  historyTiers: kScaleTiers,
  run: (ctx) async {
    await ctx.jumpTo(midHistory(ctx));
    var landFrames = 0;
    await ctx.measure('jump', primer: seatedPrimer(ctx), () async {
      for (var i = 0; i < _repeats; i++) {
        final frames = await ctx.jumpTo(i.isEven ? 0 : ctx.history - 1);
        if (frames > landFrames) landFrames = frames;
        await ctx.idle(const Duration(milliseconds: 200));
      }
    });
    ctx.record('jump', 'land_frames_max', count(landFrames));
  },
);

/// `scale.animate_far`: `animateTo` the oldest and newest message alternately.
final _animateFar = Scenario(
  id: 'scale.animate_far',
  version: 1,
  windows: const ['animate'],
  historyTiers: kScaleTiers,
  run: (ctx) async {
    await ctx.jumpTo(midHistory(ctx));
    var travel = 0;
    await ctx.measure('animate', primer: seatedPrimer(ctx), () async {
      for (var i = 0; i < _repeats; i++) {
        final end = await ctx.animateTo(
          i.isEven ? 0 : ctx.history - 1,
          const Duration(milliseconds: 800),
        );
        if (end.frames > travel) travel = end.frames;
        await ctx.idle(const Duration(milliseconds: 200));
      }
    });
    ctx.record('animate', 'travel_frames_max', count(travel));
  },
);

/// The scale family.
final scaleScenarios = <Scenario>[_fling, _jumpFar, _animateFar];
