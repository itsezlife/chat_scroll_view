/// Building blocks the scenario scripts share. Pure Dart over a
/// [ScenarioContext].
library;

import '../metrics.dart';
import '../registry.dart';

/// Legs of a drag scenario: a paced drag of [dp] over [leg], alternating
/// direction, until [total] has elapsed.
Future<void> alternatingDrags(
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

/// The message the scripts seat the viewport at: mid-history.
int midHistory(ScenarioContext ctx) => ctx.history ~/ 2;

/// A primer that touches the gesture path with a short drag, then seats the
/// viewport at mid-history again so the window starts where every run does.
Future<void> Function() seatedPrimer(ScenarioContext ctx) => () async {
  await ctx.drag(60, const Duration(milliseconds: 500));
  await ctx.jumpTo(midHistory(ctx));
};

/// What one fling did: messages the anchor moved and the settle time.
typedef FlingResult = ({int messages, Duration settle});

/// Seats mid-history, flings by [dy] over [duration], waits for the settle.
Future<FlingResult> flingTrial(
  ScenarioContext ctx,
  double dy,
  Duration duration,
) async {
  await ctx.jumpTo(midHistory(ctx));
  final before = ctx.anchorId;
  await ctx.fling(dy, duration);
  final settled = await ctx.settleTimed();
  return (messages: ctx.anchorId - before, settle: settled.time);
}

Metric exact(num value) =>
    Metric(value.toDouble(), kind: MetricKind.exact, role: MetricRole.headline);

Metric count(num value) => Metric(
  value.toDouble(),
  kind: MetricKind.count,
  role: MetricRole.diagnostic,
);

Metric ms(num value) =>
    Metric(value.toDouble(), kind: MetricKind.ms, role: MetricRole.diagnostic);
