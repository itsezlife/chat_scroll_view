/// The scenario registry: scenarios by `id@version`, filtered by glob.
///
/// Pure Dart. A scenario is a registered async function; there is no DSL
/// (spec 5).
library;

import 'bench_setup.dart';
import 'metrics.dart';

/// What a scenario sees while it runs: the one way to measure.
abstract interface class ScenarioContext {
  /// Runs [body] as the measured window [name]. Setup, warm-up and settle sit
  /// outside any window. [name] must be one the scenario declared.
  ///
  /// With a [primer], the context first settles, runs it (a low-amplitude
  /// version of the same gesture) and settles again, all outside the window,
  /// so the window does not start on a cold path. A `cold` scenario passes
  /// none.
  Future<void> measure(
    String name,
    Future<void> Function() body, {
    Future<void> Function()? primer,
  });

  /// One paced drag of [dy] logical pixels (positive is down) over
  /// [duration], one pointer move per frame, in real time.
  Future<void> drag(double dy, Duration duration);

  /// Lets every animation and fling finish.
  Future<void> settle();

  /// Like [settle], and reports how long it took (real time) and how many
  /// frames ran.
  Future<({Duration time, int frames})> settleTimed();

  /// Messages in the seeded history, ids `0..history-1`.
  int get history;

  /// The anchor message id of the viewport now.
  int get anchorId;

  /// A paced fling: one pointer move per 1/60 s, with real, monotonic
  /// timestamps, released at the end with the velocity of the stream.
  /// [dy] is the finger travel (negative is up) over [duration]. Returns at
  /// the release; the fling runs on.
  Future<void> fling(double dy, Duration duration);

  /// Touches the viewport for [hold] and lifts without moving: stops a fling.
  Future<void> touch(Duration hold);

  /// Pumps real frames for [duration].
  Future<void> idle(Duration duration);

  /// Jumps to [id], lets the viewport settle, and returns the frames it took
  /// to land.
  Future<int> jumpTo(int id);

  /// Animates to [id] over [duration] and returns the frames of the travel and
  /// where the anchor ended.
  Future<({int frames, int anchorId, double anchorOffset})> animateTo(
    int id,
    Duration duration,
  );

  /// Jumps to the newest message and returns the frames until the viewport is
  /// at the tail and has settled.
  Future<int> jumpToNewest();

  /// Grabs the scrollbar thumb (mid-history only: the thumb sits at the
  /// middle of the track there) and drags it [dy] over [duration].
  Future<void> scrollbarDrag(double dy, Duration duration);

  /// Counts the frames in which the anchor id moved by more than
  /// [thresholdMessages] since the previous frame, while [body] runs.
  Future<int> countAnchorJumps(
    Future<void> Function() body, {
    int thresholdMessages = 200,
  });

  /// Adds [metric] named [name] to the already measured window [window].
  void record(String window, String name, Metric metric);
}

/// What a scenario runs on.
enum ScenarioSubject {
  /// The suite-owned bench host: fixed minimal bubbles; the attribution
  /// baseline.
  bench,

  /// The real chat screen with its production bubbles and widgets, next to
  /// the bench runs so the bubble cost shows as a diff.
  realChat,
}

/// A registered scenario.
final class Scenario {
  const Scenario({
    required this.id,
    required this.version,
    required this.windows,
    required this.run,
    this.cold = false,
    this.setup = const BenchSetup(),
    this.deterministic = false,
    this.subject = ScenarioSubject.bench,
    this.floatingDayHeader = false,
  });

  /// `<area>.<name>`, for example `scroll.drag_slow`.
  final String id;

  /// Bumped when the script's meaning changes; marks old baselines stale.
  final int version;

  /// Names of the measured windows the script opens.
  final List<String> windows;

  final Future<void> Function(ScenarioContext ctx) run;

  /// Runs in its own launch, so the first-use cost it measures is not paid
  /// (and hidden) by an earlier scenario in the process.
  final bool cold;

  /// The data source the bench host is mounted with for this scenario.
  final BenchSetup setup;

  /// Marks a script whose scripted outcome is the same on every run: it also
  /// runs once in the traced pass (spec 7).
  final bool deterministic;

  /// The host the scenario mounts.
  final ScenarioSubject subject;

  /// Mounts the bench host with a floating day header (the date pill).
  final bool floatingDayHeader;

  /// `id@version`, the key in a metrics document.
  String get key => '$id@$version';
}

final _idPattern = RegExp(r'^[a-z0-9_]+(\.[a-z0-9_]+)+$');

/// An ordered, duplicate-free set of scenarios.
final class ScenarioRegistry {
  ScenarioRegistry(Iterable<Scenario> scenarios)
    : all = List.unmodifiable(scenarios) {
    final seen = <String>{};
    for (final s in all) {
      if (!_idPattern.hasMatch(s.id)) {
        throw ArgumentError.value(
          s.id,
          'id',
          'must be <area>.<name> (more dotted parts allowed)',
        );
      }
      if (!seen.add(s.id)) {
        throw ArgumentError.value(s.id, 'id', 'registered twice');
      }
    }
  }

  /// Every scenario, in registration order (the order they run in).
  final List<Scenario> all;

  /// `id@version` of every scenario, in order.
  List<String> get keys => [for (final s in all) s.key];

  /// The scenarios whose id matches [filter]: comma-separated globs, `*`
  /// matching any run of characters, anchored to the whole id. Empty selects
  /// all. Only scenarios whose [Scenario.cold] equals [cold] are considered:
  /// the shared-process set and the cold set are selected by separate launches.
  List<Scenario> where(String filter, {bool cold = false}) {
    final patterns = [
      for (final part in filter.split(','))
        if (part.trim().isNotEmpty) _glob(part.trim()),
    ];
    return [
      for (final s in all)
        if (s.cold == cold &&
            (patterns.isEmpty || patterns.any((p) => p.hasMatch(s.id))))
          s,
    ];
  }

  static RegExp _glob(String glob) =>
      RegExp('^${glob.split('*').map(RegExp.escape).join('.*')}\$');
}
