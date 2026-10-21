import 'dart:async';

import 'package:meta/meta.dart';
import 'package:workspace_check/src/check_plan.dart';

/// What one [CommandStep] did.
@immutable
final class StepOutcome {
  /// Creates the outcome of a step that [passed], having printed [output].
  const StepOutcome({
    required this.passed,
    required this.output,
    this.elapsed = Duration.zero,
  });

  /// Whether the command exited with 0.
  final bool passed;

  /// Everything the command printed, stdout and stderr in arrival order.
  final String output;

  /// How long the command ran.
  final Duration elapsed;
}

/// Runs a [CheckPlan]: the members side by side, each member's steps in plan
/// order, and reports the steps in plan order.
///
/// The members' gates are independent processes (an analyzer run, one test
/// process, a hook), so up to `jobs` members run at once and the check takes
/// about as long as its slowest member, not as all of them added up. A
/// member's own steps stay in order: its analysis is reported before its
/// tests, as a developer reads them.
///
/// Reporting stays in plan order, which is dependency order: a step is
/// reported once it and every step before it in the plan have finished, so
/// the log reads as a sequential run would, and a failure in a leaf still
/// comes before the failures it causes in dependents. Every step runs after
/// a failure, so one run reports everything.
abstract final class CheckRunner {
  /// Runs [steps] through [runStep], up to [jobs] members at once, calls
  /// [report] for each in plan order, and answers the labels of the steps
  /// that failed, in plan order.
  ///
  /// Members start heaviest first by [weightOf] (an estimate of how long a
  /// member takes; plan order by default), so the longest member does not
  /// start last and stretch the run. Ties keep plan order.
  static Future<List<String>> run(
    List<CommandStep> steps, {
    required int jobs,
    required Future<StepOutcome> Function(CommandStep step) runStep,
    required void Function(CommandStep step, StepOutcome outcome) report,
    int Function(String member)? weightOf,
  }) async {
    assert(jobs > 0, 'At least one member must run at a time.');
    final lanes = <String, List<int>>{};
    for (final (index, step) in steps.indexed) {
      (lanes[step.member] ??= <int>[]).add(index);
    }
    final outcomes = List<StepOutcome?>.filled(steps.length, null);
    var reported = 0;
    void reportReady() {
      while (reported < steps.length) {
        final outcome = outcomes[reported];
        if (outcome == null) return;
        report(steps[reported], outcome);
        reported++;
      }
    }

    final waiting = [
      for (final MapEntry(key: member, value: lane) in lanes.entries)
        (weight: weightOf?.call(member) ?? 0, lane: lane),
    ];
    // List.sort is not stable; the first index breaks ties in plan order.
    waiting.sort(
      (a, b) => switch (b.weight.compareTo(a.weight)) {
        0 => a.lane.first.compareTo(b.lane.first),
        final order => order,
      },
    );
    var next = 0;
    Future<void> worker() async {
      while (next < waiting.length) {
        for (final index in waiting[next++].lane) {
          outcomes[index] = await runStep(steps[index]);
          reportReady();
        }
      }
    }

    await Future.wait([
      for (var i = 0; i < jobs && i < waiting.length; i++) worker(),
    ]);
    return [
      for (final (index, step) in steps.indexed)
        if (!outcomes[index]!.passed) step.label,
    ];
  }
}
