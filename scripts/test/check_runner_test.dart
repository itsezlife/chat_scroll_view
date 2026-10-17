import 'dart:async';

import 'package:test/test.dart';
import 'package:workspace_check/workspace_check.dart';

CommandStep _step(String member, String what) => CommandStep(
  member: member,
  label: '$member: $what',
  executable: 'true',
  arguments: const <String>[],
  workingDirectory: '/repo',
);

/// Steps that finish when the test says so.
final class _Steps {
  final Map<String, Completer<StepOutcome>> _pending = {};
  final List<String> started = [];

  Future<StepOutcome> run(CommandStep step) {
    started.add(step.label);
    return (_pending[step.label] = Completer<StepOutcome>()).future;
  }

  Future<void> finish(String label, {bool passed = true}) async {
    _pending[label]!.complete(StepOutcome(passed: passed, output: label));
    // Lets the runner react: start the next step, report what is done.
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late _Steps steps;
  late List<String> reported;
  late Future<List<String>> failed;

  void start(
    List<CommandStep> plan, {
    required int jobs,
    int Function(String member)? weightOf,
  }) {
    steps = _Steps();
    reported = [];
    failed = CheckRunner.run(
      plan,
      jobs: jobs,
      weightOf: weightOf,
      runStep: steps.run,
      report: (step, outcome) => reported.add(outcome.output),
    );
  }

  test(
    'runs up to jobs members at once, each member\'s steps in order',
    () async {
      start([
        _step('a', 'analyze'),
        _step('a', 'test'),
        _step('b', 'analyze'),
        _step('c', 'analyze'),
      ], jobs: 2);
      await Future<void>.delayed(Duration.zero);

      expect(steps.started, ['a: analyze', 'b: analyze']);

      await steps.finish('a: analyze');
      expect(steps.started, ['a: analyze', 'b: analyze', 'a: test']);

      await steps.finish('b: analyze');
      expect(steps.started.last, 'c: analyze');
    },
  );

  test(
    'reports in plan order, a member whole, whoever finishes first',
    () async {
      start([
        _step('a', 'analyze'),
        _step('a', 'test'),
        _step('b', 'analyze'),
      ], jobs: 2);
      await Future<void>.delayed(Duration.zero);

      await steps.finish('b: analyze');
      expect(reported, isEmpty);

      await steps.finish('a: analyze');
      expect(reported, ['a: analyze']);

      await steps.finish('a: test');
      expect(reported, ['a: analyze', 'a: test', 'b: analyze']);
      await failed;
    },
  );

  test('keeps going after a failure and answers the failed labels in plan '
      'order', () async {
    start([
      _step('a', 'analyze'),
      _step('a', 'test'),
      _step('b', 'test'),
    ], jobs: 2);
    await Future<void>.delayed(Duration.zero);

    await steps.finish('b: test', passed: false);
    await steps.finish('a: analyze', passed: false);
    await steps.finish('a: test');

    expect(await failed, ['a: analyze', 'b: test']);
  });

  test('starts the heaviest members first and still reports in plan '
      'order', () async {
    start(
      [_step('a', 'test'), _step('b', 'test'), _step('c', 'test')],
      jobs: 1,
      weightOf: (member) => {'a': 1, 'b': 5, 'c': 3}[member]!,
    );
    await Future<void>.delayed(Duration.zero);

    expect(steps.started, ['b: test']);
    await steps.finish('b: test');
    await steps.finish('c: test');
    expect(steps.started, ['b: test', 'c: test', 'a: test']);
    expect(reported, isEmpty);

    await steps.finish('a: test');
    expect(reported, ['a: test', 'b: test', 'c: test']);
  });
}
