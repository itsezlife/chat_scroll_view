import 'package:test/test.dart';
import 'package:workspace_check/workspace_check.dart';

import 'fixture_workspace.dart';

void main() {
  late FixtureWorkspace fixture;

  setUp(() => fixture = FixtureWorkspace());
  tearDown(() => fixture.dispose());

  List<Violation> lint() =>
      PlatformForkLint.check(WorkspaceGraph.load(fixture.path));

  test('passes for a fork kept under environment_specific/', () {
    fixture.member(
      'assets',
      files: {
        'lib/src/store.dart':
            "import 'package:assets/src/environment_specific/store.dart'\n"
            '    as environment_specific;\n',
        'lib/src/environment_specific/store.dart':
            "export 'store_vm.dart' if (dart.library.js_interop) 'store_js.dart';\n",
        'lib/src/environment_specific/store_vm.dart': "import 'dart:io';\n",
        'lib/src/environment_specific/store_js.dart':
            "import 'dart:js_interop';\n"
            "import 'package:web/web.dart' as web;\n",
      },
    );

    expect(lint(), isEmpty);
  });

  test('reports a conditional directive outside environment_specific/', () {
    fixture.member(
      'assets',
      files: {
        'lib/src/store.dart':
            "import 'store_vm.dart'\n"
            "    if (dart.library.js_interop) 'store_js.dart';\n",
      },
    );

    final violations = lint();

    expect(violations.map((v) => v.rule), [
      LintRule.platformForkOutsideBoundary,
    ]);
    expect(
      violations.single.subject,
      'packages/assets/lib/src/store.dart forks on dart.library.js_interop',
    );
  });

  test('reports a platform library imported outside environment_specific/', () {
    fixture.member(
      'assets',
      files: {
        'lib/src/a.dart': "import 'dart:io';\n",
        'lib/src/b.dart':
            "import 'dart:js_interop';\n"
            "import 'package:web/web.dart';\n",
      },
    );

    expect(lint().map((v) => v.subject), [
      'packages/assets/lib/src/a.dart imports dart:io',
      'packages/assets/lib/src/b.dart imports dart:js_interop',
      'packages/assets/lib/src/b.dart imports package:web/web.dart',
    ]);
  });

  test('holds the root package and the example to the same rules', () {
    fixture
      ..write('lib/root_package.dart', "import 'dart:io';\n")
      ..member(
        'demo',
        at: 'example',
        files: {'lib/main.dart': "import 'dart:io';\n"},
      );

    expect(
      lint().map((v) => v.subject),
      unorderedEquals([
        'lib/root_package.dart imports dart:io',
        'example/lib/main.dart imports dart:io',
      ]),
    );
  });

  test('leaves the workspace\'s own command-line tool alone', () {
    fixture.member(
      'workspace_check',
      at: 'scripts',
      files: {'lib/src/gate.dart': "import 'dart:io';\n"},
    );

    expect(lint(), isEmpty);
  });
}
