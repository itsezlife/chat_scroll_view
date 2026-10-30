/// Scroll scenarios on the bench host (spec 7.1). Pure Dart: they speak only
/// to a [ScenarioContext].
library;

import '../registry.dart';

/// Legs of a drag scenario: a paced drag of [dp] over [leg], alternating
/// direction, until [total] has elapsed.
Future<void> _alternatingDrags(
  ScenarioContext ctx, {
  required double dp,
  required Duration leg,
  required Duration total,
}) async {
  final legs = total.inMilliseconds ~/ leg.inMilliseconds;
  for (var i = 0; i < legs; i++) {
    await ctx.drag(i.isEven ? dp : -dp, leg);
  }
}

/// `scroll.drag_slow`: about 400 dp per 1.5 s, alternating, 8 s.
///
/// Preceded by one unmeasured short drag so the first frames of the window are
/// not the first frames of the process.
final _dragSlow = Scenario(
  id: 'scroll.drag_slow',
  version: 1,
  windows: const ['drag'],
  run: (ctx) async {
    await ctx.drag(60, const Duration(milliseconds: 500));
    await ctx.settle();
    await ctx.measure('drag', () async {
      await _alternatingDrags(
        ctx,
        dp: 400,
        leg: const Duration(milliseconds: 1500),
        total: const Duration(seconds: 8),
      );
    });
    await ctx.settle();
  },
);

/// The scroll family registered so far.
final scrollScenarios = ScenarioRegistry([_dragSlow]);
