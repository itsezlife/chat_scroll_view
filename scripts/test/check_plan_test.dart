import 'package:test/test.dart';
import 'package:workspace_check/workspace_check.dart';

void main() {
  WorkspaceGraph graphOf(List<WorkspaceMember> members) =>
      WorkspaceGraph(root: '/repo', members: members);

  List<String> labels(WorkspaceGraph graph) =>
      CheckPlan.forWorkspace(graph).map((s) => s.label).toList();

  const model = WorkspaceMember(
    name: 'model',
    path: 'packages/model',
    analysisTargets: ['lib', 'test'],
    hasTests: true,
  );
  const widgets = WorkspaceMember(
    name: 'widgets',
    path: 'packages/widgets',
    dependencies: {'model'},
    usesFlutter: true,
    analysisTargets: ['lib', 'test', 'integration_test'],
    hasTests: true,
  );

  test('analyzes and tests each member after the members it depends on', () {
    expect(labels(graphOf([widgets, model])), [
      'model: analyze',
      'model: test',
      'widgets: analyze',
      'widgets: test',
    ]);
  });

  test('analyzes with --fatal-infos over the existing layout directories', () {
    final analyze = CheckPlan.forWorkspace(graphOf([widgets])).first;

    expect(analyze.executable, 'dart');
    expect(analyze.arguments, [
      'analyze',
      '--fatal-infos',
      'lib',
      'test',
      'integration_test',
    ]);
    expect(analyze.workingDirectory, '/repo/packages/widgets');
  });

  test('runs flutter test for Flutter members and dart test for the rest', () {
    final steps = CheckPlan.forWorkspace(graphOf([widgets, model]));

    final modelTest = steps.singleWhere((s) => s.label == 'model: test');
    final widgetsTest = steps.singleWhere((s) => s.label == 'widgets: test');

    expect([modelTest.executable, ...modelTest.arguments], ['dart', 'test']);
    expect(
      [widgetsTest.executable, ...widgetsTest.arguments],
      ['flutter', 'test', '--no-pub'],
    );
  });

  test('skips tests for a member without any test file', () {
    const bare = WorkspaceMember(
      name: 'bare',
      path: 'packages/bare',
      analysisTargets: ['lib'],
    );

    expect(labels(graphOf([bare])), ['bare: analyze']);
  });

  test('skips analysis for a member with no Dart directories', () {
    const empty = WorkspaceMember(name: 'empty', path: 'packages/empty');

    expect(labels(graphOf([empty])), isEmpty);
  });

  test(
    'runs a member\'s tool/check hook after its tests, from its directory',
    () {
      const generator = WorkspaceMember(
        name: 'generator',
        path: 'packages/generator',
        analysisTargets: ['lib', 'test', 'tool'],
        hasTests: true,
        hasCheckHook: true,
      );

      final steps = CheckPlan.forWorkspace(graphOf([generator]));

      expect(steps.map((s) => s.label), [
        'generator: analyze',
        'generator: test',
        'generator: tool/check',
      ]);
      expect(steps.last.executable, '/repo/packages/generator/tool/check');
      expect(steps.last.workingDirectory, '/repo/packages/generator');
    },
  );

  test('the root package runs from the workspace root', () {
    const root = WorkspaceMember(
      name: 'root',
      path: '.',
      analysisTargets: ['lib'],
    );

    expect(
      CheckPlan.forWorkspace(graphOf([root])).single.workingDirectory,
      '/repo',
    );
  });

  test('describes a step as the command a developer could paste', () {
    expect(
      CheckPlan.forWorkspace(graphOf([model])).first.commandLine,
      'dart analyze --fatal-infos lib test',
    );
  });
}
