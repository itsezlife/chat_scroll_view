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
/// Primed by one short, low-amplitude drag the context runs after an idle
/// settle, outside the window.
final _dragSlow = Scenario(
  id: 'scroll.drag_slow',
  version: 2,
  windows: const ['drag'],
  run: (ctx) => ctx.measure(
    'drag',
    primer: () => ctx.drag(60, const Duration(milliseconds: 500)),
    () => _alternatingDrags(
      ctx,
      dp: 400,
      leg: const Duration(milliseconds: 1500),
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
    () => _alternatingDrags(
      ctx,
      dp: 400,
      leg: const Duration(milliseconds: 1500),
      total: const Duration(seconds: 3),
    ),
  ),
);

/// The scroll family registered so far.
final scrollScenarios = ScenarioRegistry([_dragSlow, _firstScroll]);
