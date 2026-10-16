/// The pass/fail rule of the panel acceptance test, and the proof that the
/// fling covered the catalogue.
///
/// Pure Dart: shared by the on-device test and the unit tests.
library;

import 'dart:math' as math;

import 'frame_metrics.dart';

/// Thresholds a scenario must meet. The defaults are the binding bar from the
/// spec: no frame over one vsync budget, raster p99 at most 2 ms.
final class AcceptanceCriteria {
  const AcceptanceCriteria({
    this.maxOverBudgetFrames = 0,
    this.maxRasterP99Ms = 2,
  });

  final int maxOverBudgetFrames;
  final double maxRasterP99Ms;
}

/// Outcome of judging one scenario: [failures] is empty exactly when it passed.
final class Verdict {
  const Verdict(this.failures);

  final List<String> failures;

  bool get passed => failures.isEmpty;
}

/// Most raw bytes the resident glyph atlas pages may take while the panel is
/// open (64 MiB).
const int kResidentPageCeilingBytes = 64 * 1024 * 1024;

/// How much of the catalogue shown by the viewport could be drawn from baked
/// pages when a scenario ended.
///
/// A fling is judged on smoothness, and a fling over circles is smooth too: the
/// circle placeholder costs next to nothing. Without this a cold first pass
/// could go green while never touching the sprite path it is there to measure.
/// The scenario settles (the bake runs while nothing scrolls) before it ends,
/// so a catalogue that is not drawable by then means the bake did not keep up,
/// and the return leg of the fling ran over circles. It is measured at the end
/// of the scenario, not per frame.
final class BakeCoverage {
  const BakeCoverage({required this.bakedGlyphs, required this.shownGlyphs});

  /// Distinct glyphs of the catalogue that had a sprite.
  final int bakedGlyphs;

  /// Distinct glyphs of the catalogue the viewport shows.
  final int shownGlyphs;

  /// Smallest [fraction] counted as the catalogue being baked.
  static const double minFraction = 0.99;

  double get fraction => shownGlyphs <= 0 ? 0 : bakedGlyphs / shownGlyphs;

  bool get isComplete => shownGlyphs > 0 && fraction >= minFraction;

  String describe() =>
      '$bakedGlyphs of $shownGlyphs glyphs drawable '
      '(${(fraction * 100).toStringAsFixed(1)}%)';

  Map<String, Object?> toJson() => {
    'bakedGlyphs': bakedGlyphs,
    'shownGlyphs': shownGlyphs,
    'fraction': fraction,
    'complete': isComplete,
  };
}

/// Judges [stats] against [criteria], [coverage] when the scenario flings, and
/// [residentBytes] (what the atlas held when the scenario ended) against
/// [kResidentPageCeilingBytes] when the platform has an atlas, and [bake] when
/// the scenario must have flung over baked sprites.
///
/// Every failed criterion is reported, so one red run names all that is wrong.
/// A scenario that recorded no frames fails: silence is not smoothness.
Verdict judge(
  FrameStats stats, {
  AcceptanceCriteria criteria = const AcceptanceCriteria(),
  FlingCoverage? coverage,
  int? residentBytes,
  BakeCoverage? bake,
}) {
  final failures = <String>[];
  if (stats.frames == 0) {
    failures.add('no frames were recorded');
  } else {
    if (stats.overBudgetFrames > criteria.maxOverBudgetFrames) {
      failures.add(
        '${stats.overBudgetFrames} of ${stats.frames} frames over the '
        '${stats.budgetMs.toStringAsFixed(2)} ms vsync budget '
        '(allowed ${criteria.maxOverBudgetFrames}); '
        'raster max ${stats.rasterMaxMs.toStringAsFixed(1)} ms',
      );
    }
    if (stats.rasterP99Ms > criteria.maxRasterP99Ms) {
      failures.add(
        'raster p99 ${stats.rasterP99Ms.toStringAsFixed(2)} ms '
        '(allowed ${criteria.maxRasterP99Ms} ms)',
      );
    }
  }
  if (coverage != null && !coverage.isComplete) {
    failures.add('fling coverage incomplete: ${coverage.describe()}');
  }
  if (bake != null && !bake.isComplete) {
    failures.add(
      'the catalogue was not baked when the scenario ended: '
      '${bake.describe()}; the fling ran over circles, not sprites',
    );
  }
  if (residentBytes != null && residentBytes > kResidentPageCeilingBytes) {
    failures.add(
      'resident emoji pages ${(residentBytes / (1024 * 1024)).toStringAsFixed(1)} '
      'MiB (allowed ${kResidentPageCeilingBytes ~/ (1024 * 1024)} MiB)',
    );
  }
  return Verdict(failures);
}

/// Evidence that a fling script travelled the whole catalogue and back.
///
/// Without it a green run could mean the fling never left the first screen.
/// Two independent signals must agree: the offset stopped advancing at the end
/// ([reachedEnd]), and the span the viewport showed matches the content extent
/// estimated from the catalogue itself ([fraction]).
final class FlingCoverage {
  const FlingCoverage({
    required this.reachedEnd,
    required this.returnedToTop,
    required this.maxOffsetPx,
    required this.viewportHeightPx,
    required this.expectedExtentPx,
  });

  /// Further downward flings no longer moved the offset.
  final bool reachedEnd;

  /// The fling back up ended within the first screen.
  final bool returnedToTop;

  /// Highest scroll offset observed.
  final double maxOffsetPx;

  final double viewportHeightPx;

  /// Content extent estimated from the catalogue (see [estimateContentExtent]).
  final double expectedExtentPx;

  /// Smallest [fraction] still counted as the whole catalogue; the estimate
  /// ignores padding, so a little slack is expected either way.
  static const double minFraction = 0.95;

  /// Share of the catalogue the viewport has shown at the highest offset.
  double get fraction => expectedExtentPx <= 0
      ? 0
      : math.min(1, (maxOffsetPx + viewportHeightPx) / expectedExtentPx);

  bool get isComplete => reachedEnd && returnedToTop && fraction >= minFraction;

  String describe() =>
      'reachedEnd=$reachedEnd returnedToTop=$returnedToTop '
      'maxOffset=${maxOffsetPx.toStringAsFixed(0)}px '
      'of ~${expectedExtentPx.toStringAsFixed(0)}px '
      '(${(fraction * 100).toStringAsFixed(1)}%)';

  Map<String, Object?> toJson() => {
    'reachedEnd': reachedEnd,
    'returnedToTop': returnedToTop,
    'maxOffsetPx': maxOffsetPx,
    'viewportHeightPx': viewportHeightPx,
    'expectedExtentPx': expectedExtentPx,
    'fraction': fraction,
    'complete': isComplete,
  };
}

/// Content height the viewport lays out for a sectioned grid: one header per
/// section plus one [cellExtent] row per [spanCount] leaves. Padding is left
/// out, so this is a slight under-estimate.
double estimateContentExtent({
  required List<int> leavesPerSection,
  required int spanCount,
  required double cellExtent,
  required double headerExtent,
}) {
  var rows = 0;
  for (final leaves in leavesPerSection) {
    rows += (leaves / spanCount).ceil();
  }
  return leavesPerSection.length * headerExtent + rows * cellExtent;
}

/// The panel open animation, measured from the first frame of the open.
const String kPanelOpenScenario = 'panel_open';

/// First fling over the whole catalogue with every glyph unseen by the engine.
const String kColdFirstPassScenario = 'cold_first_pass';

/// Scenarios whose verdict decides the bare-panel run; others are diagnostics.
const List<String> kAssertedScenarios = [
  kPanelOpenScenario,
  kColdFirstPassScenario,
];

/// The panel open animation over the real chat screen.
const String kChatPanelOpenScenario = 'chat_panel_open';

/// The same cold first fling, with the panel hosted on the real chat screen.
const String kChatColdFirstPassScenario = 'chat_cold_first_pass';

/// First launch ever: the emoji cache is empty, so the panel shows circles
/// while the atlas bakes. Circles may last as long as they last; a dropped
/// frame may not.
const String kFirstRunScenario = 'first_run_no_cache';

/// A later launch with a valid cache: the atlas restores its pages instead of
/// baking. Circles must not outlast [kCachedCircleBudget] and the panel open
/// animation drops no frame.
const String kCachedColdStartScenario = 'cold_start_valid_cache';

/// The launch after an OS or emoji font update (the art version changed): the
/// old pages keep drawing while the new set bakes, then swap once. Diagnostic:
/// recorded, not asserted, until it has been measured on the reference device.
const String kOsUpdateScenario = 'os_update_stale_rebake';

/// The longest circles may last on a cold start with a valid cache.
const Duration kCachedCircleBudget = Duration(milliseconds: 500);

/// One test target and the scenarios it must report to count as a pass.
///
/// Each suite is its own launch: the engine's glyph atlas is cold only in a
/// fresh process, so two suites cannot share one without the second measuring
/// a warm pass.
final class AcceptanceSuite {
  const AcceptanceSuite({
    required this.name,
    required this.target,
    required this.assertedScenarios,
  });

  /// Short name on the command line.
  final String name;

  /// `integration_test` entry point, relative to the example directory.
  final String target;

  /// Scenarios whose verdict decides a launch of this suite.
  final List<String> assertedScenarios;
}

/// The bare panel on a scaffold: no chat, no backend.
const AcceptanceSuite kBareSuite = AcceptanceSuite(
  name: 'bare',
  target: 'integration_test/all_tests.dart',
  assertedScenarios: kAssertedScenarios,
);

/// The panel opened from the composer of the real chat screen, over generated
/// messages. Catches jank from the chat behind, the glass and neighbours.
const AcceptanceSuite kChatSuite = AcceptanceSuite(
  name: 'chat',
  target: 'integration_test/panel_over_chat_test.dart',
  assertedScenarios: [kChatPanelOpenScenario, kChatColdFirstPassScenario],
);

/// The emoji cache flows: first run with no cache, cold start with a valid
/// cache, and (diagnostic) the launch after an OS update. One launch runs the
/// three in order against one cache directory that is fresh for the launch, so
/// the first really is a first run.
const AcceptanceSuite kFirstRunSuite = AcceptanceSuite(
  name: 'first_run',
  target: 'integration_test/panel_first_run_test.dart',
  assertedScenarios: [kFirstRunScenario, kCachedColdStartScenario],
);

const List<AcceptanceSuite> kSuites = [kBareSuite, kChatSuite, kFirstRunSuite];

/// The suite called [name], or null.
AcceptanceSuite? suiteNamed(String name) {
  for (final suite in kSuites) {
    if (suite.name == name) return suite;
  }
  return null;
}
