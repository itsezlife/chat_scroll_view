import 'package:test/test.dart';
import 'package:workspace_check/workspace_check.dart';

import 'fixture_workspace.dart';

void main() {
  late FixtureWorkspace fixture;

  setUp(() {
    fixture = FixtureWorkspace()
      ..member('alpha', files: {'lib/alpha.dart': ''})
      ..member('beta', files: {'lib/beta.dart': ''});
  });
  tearDown(() => fixture.dispose());

  List<Violation> lint() =>
      ReexportLint.check(WorkspaceGraph.load(fixture.path));

  test('passes when packages only re-export themselves and outsiders', () {
    fixture.write(
      'packages/alpha/lib/alpha.dart',
      "export 'src/a.dart';\n"
          "export 'package:alpha/src/b.dart';\n"
          "export 'package:flutter_md/flutter_md.dart';\n"
          "import 'package:beta/beta.dart';\n",
    );

    expect(lint(), isEmpty);
  });

  test('reports a package re-exporting another workspace package', () {
    fixture.write(
      'packages/alpha/lib/alpha.dart',
      "export 'package:beta/beta.dart';\n",
    );

    final violations = lint();

    expect(violations.map((v) => v.rule), [LintRule.crossPackageReexport]);
    expect(
      violations.single.subject,
      'packages/alpha/lib/alpha.dart exports package:beta/beta.dart',
    );
  });

  test('reports a re-export that spans lines and narrows with show', () {
    fixture.write(
      'packages/alpha/lib/alpha.dart',
      "export 'package:beta/beta.dart'\n    show Thing;\n",
    );

    expect(lint().map((v) => v.rule), [LintRule.crossPackageReexport]);
  });

  test('reports a conditional export that reaches another package', () {
    fixture.write(
      'packages/alpha/lib/alpha.dart',
      "export 'stub.dart' if (dart.library.io) 'package:beta/io.dart';\n",
    );

    expect(lint().single.subject, endsWith('exports package:beta/io.dart'));
  });

  test('finds a re-export deep under lib/src', () {
    fixture.write(
      'packages/alpha/lib/src/deep/inner.dart',
      "export 'package:beta/beta.dart';\n",
    );

    expect(
      lint().single.subject,
      startsWith('packages/alpha/lib/src/deep/inner.dart'),
    );
  });

  test('the root package and example are scanned like any member', () {
    fixture.member(
      'example_app',
      at: 'example',
      files: {'lib/main.dart': "export 'package:alpha/alpha.dart';\n"},
    );

    expect(lint().single.subject, startsWith('example/lib/main.dart'));
  });

  test('does not look outside lib/', () {
    fixture.write(
      'packages/alpha/test/helper.dart',
      "export 'package:beta/beta.dart';\n",
    );

    expect(lint(), isEmpty);
  });
}
