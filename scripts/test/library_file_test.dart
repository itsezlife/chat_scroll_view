import 'package:test/test.dart';
import 'package:workspace_check/workspace_check.dart';

import 'fixture_workspace.dart';

void main() {
  group('DartDirective.scan', () {
    // Lists inside records compare by identity, so flatten to a string.
    List<String> scan(String source) => [
      for (final d in DartDirective.scan(source))
        '${d.kind.name} ${d.uris.join(' ')}',
    ];

    test('reads imports and exports with either quote style', () {
      expect(
        scan(
          "import 'dart:async';\n"
          'export "package:a/a.dart";\n'
          "import 'b.dart' as b;\n",
        ),
        ['import dart:async', 'export package:a/a.dart', 'import b.dart'],
      );
    });

    test('reads a directive that spans lines, including its combinators', () {
      expect(
        scan(
          "export 'package:a/a.dart'\n"
          '    show One,\n'
          '        Two;\n',
        ),
        ['export package:a/a.dart'],
      );
    });

    test('collects every URI of a conditional directive', () {
      expect(
        scan(
          "export 'stub.dart'\n"
          "    if (dart.library.io) 'package:a/io.dart'\n"
          "    if (dart.library.js_interop) 'web.dart';\n",
        ),
        ['export stub.dart package:a/io.dart web.dart'],
      );
    });

    test('ignores comments, part directives and library declarations', () {
      expect(
        scan(
          "// export 'package:a/a.dart';\n"
          "/// import 'package:b/b.dart';\n"
          'library foo;\n'
          "part 'foo.g.dart';\n",
        ),
        isEmpty,
      );
    });
  });

  group('LibraryFile.allIn', () {
    test(
      'lists only lib/ Dart files, with member- and repo-relative paths',
      () {
        final fixture = FixtureWorkspace();
        addTearDown(fixture.dispose);
        fixture.member(
          'alpha',
          files: {
            'lib/alpha.dart': "export 'src/a.dart';\n",
            'lib/src/a.dart': '',
            'lib/src/data.json': '{}',
            'test/a_test.dart': '',
          },
        );
        final graph = WorkspaceGraph.load(fixture.path);

        final files = LibraryFile.allIn(graph, graph.member('alpha')!);

        expect(files.map((f) => f.libPath), ['alpha.dart', 'src/a.dart']);
        expect(files.map((f) => f.repoPath), [
          'packages/alpha/lib/alpha.dart',
          'packages/alpha/lib/src/a.dart',
        ]);
        expect(files.first.directives.single.uris, ['src/a.dart']);
      },
    );
  });
}
