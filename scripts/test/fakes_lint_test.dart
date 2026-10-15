import 'package:test/test.dart';
import 'package:workspace_check/workspace_check.dart';

import 'fixture_workspace.dart';

void main() {
  late FixtureWorkspace fixture;

  setUp(() {
    fixture = FixtureWorkspace()
      ..member('alpha', files: {'lib/alpha.dart': '', 'lib/testing.dart': ''})
      ..member('beta', files: {'lib/beta.dart': '', 'lib/testing.dart': ''});
  });
  tearDown(() => fixture.dispose());

  List<Violation> lint() => FakesLint.check(WorkspaceGraph.load(fixture.path));

  List<String> subjects() => lint().map((v) => v.subject).toList();

  group('accepts', () {
    test('fakes exported from testing.dart and nowhere else', () {
      fixture
        ..write(
          'packages/alpha/lib/testing.dart',
          "export 'src/testing/fake_store.dart';\n"
              "export 'package:alpha/src/fakes/memory.dart';\n",
        )
        ..write('packages/alpha/lib/src/testing/fake_store.dart', '')
        ..write('packages/alpha/lib/src/fakes/memory.dart', '')
        ..write('packages/alpha/lib/alpha.dart', "export 'src/store.dart';\n");

      expect(lint(), isEmpty);
    });

    test('testing code importing another package\'s testing.dart', () {
      fixture
        ..write(
          'packages/beta/lib/testing.dart',
          "import 'package:alpha/testing.dart';\n",
        )
        ..write(
          'packages/beta/lib/src/testing/fake_x.dart',
          "import 'package:alpha/testing.dart';\n",
        )
        ..write(
          'packages/beta/lib/src/fake_y.dart',
          "import 'package:alpha/testing.dart';\n",
        )
        ..write(
          'packages/beta/lib/src/z_fake.dart',
          "import 'package:alpha/testing.dart';\n",
        );

      expect(lint(), isEmpty);
    });

    test(
      'production code importing ordinary files whose names merely resemble fakes',
      () {
        fixture
          ..write('packages/alpha/lib/src/fakery/thing.dart', '')
          ..write('packages/alpha/lib/src/fakeable.dart', '')
          ..write('packages/alpha/lib/src/testing_hooks.dart', '')
          ..write(
            'packages/alpha/lib/alpha.dart',
            "export 'src/fakery/thing.dart';\n"
                "export 'src/fakeable.dart';\n"
                "import 'src/testing_hooks.dart';\n",
          );

        expect(lint(), isEmpty);
      },
    );

    test('tests and other directories using fakes freely', () {
      fixture
        ..write(
          'packages/beta/test/b_test.dart',
          "import 'package:alpha/testing.dart';\n",
        )
        ..write(
          'packages/beta/tool/gen.dart',
          "import 'package:alpha/testing.dart';\n",
        );

      expect(lint(), isEmpty);
    });
  });

  group('exports of fakes outside testing.dart', () {
    test('by file name, from the public barrel', () {
      fixture.write(
        'packages/alpha/lib/alpha.dart',
        "export 'src/fake_catalog_cache.dart';\n",
      );
      fixture.write('packages/alpha/lib/src/fake_catalog_cache.dart', '');

      expect(lint().map((v) => v.rule), [LintRule.fakeExportedOutsideTesting]);
      expect(subjects(), [
        'packages/alpha/lib/alpha.dart exports src/fake_catalog_cache.dart',
      ]);
    });

    test('by directory, through the package: URI of the same package', () {
      fixture.write(
        'packages/alpha/lib/alpha.dart',
        "export 'package:alpha/src/testing/store.dart';\n",
      );

      expect(lint().map((v) => v.rule), [LintRule.fakeExportedOutsideTesting]);
    });

    test('of the testing.dart entry point itself', () {
      fixture.write(
        'packages/alpha/lib/alpha.dart',
        "export 'testing.dart';\n",
      );

      expect(lint().map((v) => v.rule), [LintRule.fakeExportedOutsideTesting]);
    });

    test('through a relative path that climbs out of a subdirectory', () {
      fixture.write(
        'packages/alpha/lib/src/deep/barrel.dart',
        "export '../fakes/memory.dart';\n",
      );

      expect(subjects(), [
        'packages/alpha/lib/src/deep/barrel.dart exports ../fakes/memory.dart',
      ]);
    });
  });

  group('imports of fakes by production code', () {
    test('of another package\'s testing.dart', () {
      fixture.write(
        'packages/beta/lib/src/uses.dart',
        "import 'package:alpha/testing.dart';\n",
      );

      expect(lint().map((v) => v.rule), [LintRule.fakeImportedByProduction]);
      expect(subjects(), [
        'packages/beta/lib/src/uses.dart imports package:alpha/testing.dart',
      ]);
    });

    test('of its own fake sources', () {
      fixture.write(
        'packages/alpha/lib/src/store.dart',
        "import 'testing/fake_store.dart';\n",
      );

      expect(lint().map((v) => v.rule), [LintRule.fakeImportedByProduction]);
    });

    test('from the example host\'s lib/', () {
      fixture.member(
        'host_app',
        at: 'example',
        files: {'lib/main.dart': "import 'package:alpha/testing.dart';\n"},
      );

      expect(subjects(), [
        'example/lib/main.dart imports package:alpha/testing.dart',
      ]);
    });

    test('a package named like a workspace member but outside it is fine', () {
      fixture.write(
        'packages/alpha/lib/src/uses.dart',
        "import 'package:outsider/testing.dart';\n",
      );

      expect(lint(), isEmpty);
    });
  });
}
