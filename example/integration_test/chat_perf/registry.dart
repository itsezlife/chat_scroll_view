/// The scenario registry: scenarios by `id@version`, filtered by glob.
///
/// Pure Dart. A scenario is a registered async function; there is no DSL
/// (spec 5).
library;

/// What a scenario sees while it runs: the one way to measure.
abstract interface class ScenarioContext {
  /// Runs [body] as the measured window [name]. Setup, warm-up and settle sit
  /// outside any window. [name] must be one the scenario declared.
  Future<void> measure(String name, Future<void> Function() body);

  /// One paced drag of [dy] logical pixels (positive is down) over
  /// [duration], one pointer move per frame, in real time.
  Future<void> drag(double dy, Duration duration);

  /// Lets every animation and fling finish.
  Future<void> settle();
}

/// A registered scenario.
final class Scenario {
  const Scenario({
    required this.id,
    required this.version,
    required this.windows,
    required this.run,
  });

  /// `<area>.<name>`, for example `scroll.drag_slow`.
  final String id;

  /// Bumped when the script's meaning changes; marks old baselines stale.
  final int version;

  /// Names of the measured windows the script opens.
  final List<String> windows;

  final Future<void> Function(ScenarioContext ctx) run;

  /// `id@version`, the key in a metrics document.
  String get key => '$id@$version';
}

final _idPattern = RegExp(r'^[a-z0-9_]+\.[a-z0-9_]+$');

/// An ordered, duplicate-free set of scenarios.
final class ScenarioRegistry {
  ScenarioRegistry(Iterable<Scenario> scenarios)
    : all = List.unmodifiable(scenarios) {
    final seen = <String>{};
    for (final s in all) {
      if (!_idPattern.hasMatch(s.id)) {
        throw ArgumentError.value(s.id, 'id', 'must be <area>.<name>');
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
  /// all.
  List<Scenario> where(String filter) {
    final patterns = [
      for (final part in filter.split(','))
        if (part.trim().isNotEmpty) _glob(part.trim()),
    ];
    if (patterns.isEmpty) return all;
    return [
      for (final s in all)
        if (patterns.any((p) => p.hasMatch(s.id))) s,
    ];
  }

  static RegExp _glob(String glob) =>
      RegExp('^${glob.split('*').map(RegExp.escape).join('.*')}\$');
}
