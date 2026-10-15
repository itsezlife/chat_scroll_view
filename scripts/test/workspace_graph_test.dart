import 'package:test/test.dart';
import 'package:workspace_check/workspace_check.dart';

import 'fixture_workspace.dart';

void main() {
  late FixtureWorkspace fixture;

  setUp(() => fixture = FixtureWorkspace());
  tearDown(() => fixture.dispose());

  group('WorkspaceGraph.load', () {
    test('lists the root package and every member with relative paths', () {
      fixture
        ..member('alpha')
        ..member('beta', at: 'example');

      final graph = WorkspaceGraph.load(fixture.path);

      expect(graph.members.map((m) => m.name), [
        'alpha',
        'beta',
        'root_package',
      ]);
      expect(graph.member('root_package')!.path, '.');
      expect(graph.member('alpha')!.path, 'packages/alpha');
      expect(graph.member('beta')!.path, 'example');
    });

    test('counts dev_dependencies as dependencies on workspace members', () {
      fixture
        ..member('alpha')
        ..member('beta', dependencies: ['alpha', 'meta'])
        ..member('gamma', devDependencies: ['beta']);

      final graph = WorkspaceGraph.load(fixture.path);

      expect(graph.dependenciesOf(graph.member('beta')!), {'alpha'});
      expect(graph.dependenciesOf(graph.member('gamma')!), {'beta'});
    });

    test('a member that needs the Flutter SDK is not a pure-Dart member', () {
      fixture
        ..member('plain', dependencies: ['meta'])
        ..member('widgets', dependencies: ['flutter'])
        ..member('tested', devDependencies: ['flutter_test']);

      final graph = WorkspaceGraph.load(fixture.path);

      expect(graph.member('plain')!.usesFlutter, isFalse);
      expect(graph.member('widgets')!.usesFlutter, isTrue);
      expect(graph.member('tested')!.usesFlutter, isTrue);
    });

    test('records which pub layout directories, tests and hook exist', () {
      fixture.member(
        'alpha',
        files: {
          'lib/alpha.dart': '',
          'test/alpha_test.dart': '',
          'tool/check': '#!/usr/bin/env bash\n',
        },
      );
      fixture.member('bare');

      final graph = WorkspaceGraph.load(fixture.path);
      final alpha = graph.member('alpha')!;
      final bare = graph.member('bare')!;

      expect(alpha.analysisTargets, ['lib', 'test', 'tool']);
      expect(alpha.hasTests, isTrue);
      expect(alpha.hasCheckHook, isTrue);
      expect(bare.analysisTargets, isEmpty);
      expect(bare.hasTests, isFalse);
      expect(bare.hasCheckHook, isFalse);
    });

    test('rejects a pubspec that is not a workspace root', () {
      fixture.write('pubspec.yaml', 'name: lonely\n');

      expect(
        () => WorkspaceGraph.load(fixture.path),
        throwsA(isA<WorkspaceException>()),
      );
    });

    test('rejects a listed member without a pubspec', () {
      fixture.write(
        'pubspec.yaml',
        'name: root_package\nworkspace:\n  - packages/ghost\n',
      );

      expect(
        () => WorkspaceGraph.load(fixture.path),
        throwsA(
          isA<WorkspaceException>().having(
            (e) => e.message,
            'message',
            contains('packages/ghost'),
          ),
        ),
      );
    });

    test('rejects a package under packages/ that is not listed', () {
      fixture.member('alpha');
      fixture.write('packages/forgotten/pubspec.yaml', 'name: forgotten\n');

      expect(
        () => WorkspaceGraph.load(fixture.path),
        throwsA(
          isA<WorkspaceException>().having(
            (e) => e.message,
            'message',
            contains('packages/forgotten'),
          ),
        ),
      );
    });

    test('rejects an example/ package that is not listed', () {
      fixture.member('alpha');
      fixture.write('example/pubspec.yaml', 'name: demo\n');

      expect(
        () => WorkspaceGraph.load(fixture.path),
        throwsA(
          isA<WorkspaceException>().having(
            (e) => e.message,
            'message',
            contains('example'),
          ),
        ),
      );
    });

    test('rejects glob entries instead of silently matching nothing', () {
      fixture.write(
        'pubspec.yaml',
        'name: root_package\nworkspace:\n  - packages/*\n',
      );

      expect(
        () => WorkspaceGraph.load(fixture.path),
        throwsA(isA<WorkspaceException>()),
      );
    });
  });

  group('WorkspaceGraph.inDependencyOrder', () {
    WorkspaceMember member(
      String name, [
      Set<String> dependencies = const {},
    ]) => WorkspaceMember(
      name: name,
      path: 'packages/$name',
      dependencies: dependencies,
    );

    List<String> order(List<WorkspaceMember> members) => WorkspaceGraph(
      root: '.',
      members: members,
    ).inDependencyOrder().map((m) => m.name).toList();

    test('puts dependencies first, visiting members alphabetically', () {
      expect(
        order([
          member('app', {'pages', 'model'}),
          member('pages', {'model'}),
          member('model'),
          member('assets'),
        ]),
        ['model', 'pages', 'app', 'assets'],
      );
    });

    test('terminates on a cycle and still lists every member once', () {
      expect(
        order([
          member('a', {'b'}),
          member('b', {'a'}),
        ]),
        ['b', 'a'],
      );
    });
  });
}
