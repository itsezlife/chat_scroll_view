import 'package:test/test.dart';
import 'package:workspace_check/workspace_check.dart';

import 'fixture_workspace.dart';

void main() {
  late FixtureWorkspace fixture;

  setUp(() => fixture = FixtureWorkspace());
  tearDown(() => fixture.dispose());

  List<Violation> lint() =>
      TestEntrypointLint.check(WorkspaceGraph.load(fixture.path));

  test('passes when the entrypoint imports every test file', () {
    fixture.member(
      'alpha',
      files: {
        'test/a_test.dart': '',
        'test/deep/b_test.dart': '',
        'test/support/helpers.dart': '',
        'test/unit_test.dart':
            "import 'package:test/test.dart';\n"
            "import 'a_test.dart' as a_test;\n"
            'import "deep/b_test.dart"\n    as b_test;\n',
      },
    );
    fixture.member('bare', files: {'lib/bare.dart': ''});

    expect(lint(), isEmpty);
  });

  test('reports a member with tests and no entrypoint', () {
    fixture.member('alpha', files: {'test/a_test.dart': ''});

    final violations = lint();

    expect(violations.map((v) => v.rule), [LintRule.testOutsideEntrypoint]);
    expect(
      violations.single.subject,
      'packages/alpha/test/unit_test.dart is missing',
    );
  });

  test('reports each test file the entrypoint does not import', () {
    fixture.member(
      'alpha',
      files: {
        'test/a_test.dart': '',
        'test/deep/b_test.dart': '',
        'test/c_test.dart': '',
        'test/unit_test.dart': "import 'a_test.dart' as a_test;\n",
      },
    );

    expect(lint().map((v) => v.subject), [
      'packages/alpha/test/c_test.dart is not run by test/unit_test.dart',
      'packages/alpha/test/deep/b_test.dart is not run by test/unit_test.dart',
    ]);
  });

  test('does not count a commented-out import', () {
    fixture.member(
      'alpha',
      files: {
        'test/a_test.dart': '',
        'test/unit_test.dart': "// import 'a_test.dart' as a_test;\n",
      },
    );

    expect(lint(), hasLength(1));
  });
}
