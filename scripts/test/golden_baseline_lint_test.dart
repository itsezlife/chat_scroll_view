import 'package:test/test.dart';
import 'package:workspace_check/workspace_check.dart';

import 'fixture_workspace.dart';

void main() {
  late FixtureWorkspace fixture;

  setUp(() => fixture = FixtureWorkspace()..member('alpha'));
  tearDown(() => fixture.dispose());

  List<String> subjects() => GoldenBaselineLint.check(
    WorkspaceGraph.load(fixture.path),
  ).map((v) => v.subject).toList();

  const baseline = '''
void main() {
  useGoldenBaselines('test/rows_golden_test.dart');
  testWidgets('a row', (tester) async {
    await expectLater(find.byType(Row), matchesGoldenFile('row.png'));
  });
}
''';

  test('a golden test through useGoldenBaselines passes', () {
    fixture.write('packages/alpha/test/rows_golden_test.dart', baseline);

    expect(subjects(), isEmpty);
  });

  test('a golden test without useGoldenBaselines is reported', () {
    fixture.write(
      'packages/alpha/test/rows_golden_test.dart',
      baseline.replaceFirst(
        "  useGoldenBaselines('test/rows_golden_test.dart');\n",
        '',
      ),
    );

    expect(subjects(), [
      'packages/alpha/test/rows_golden_test.dart compares goldens without '
          'useGoldenBaselines',
    ]);
  });

  test('assigning goldenFileComparator is reported', () {
    fixture.write(
      'packages/alpha/test/rows_golden_test.dart',
      baseline.replaceFirst(
        'void main() {\n',
        'void main() {\n  goldenFileComparator = LocalFileComparator(uri);\n',
      ),
    );

    expect(subjects(), [
      'packages/alpha/test/rows_golden_test.dart installs its own golden '
          'comparator',
    ]);
  });

  test('a comparator class in a support file is reported', () {
    fixture.write(
      'packages/alpha/test/support/tolerant.dart',
      'class Tolerant extends LocalFileComparator {}\n',
    );

    expect(subjects(), [
      'packages/alpha/test/support/tolerant.dart installs its own golden '
          'comparator',
    ]);
  });

  test('reading goldenFileComparator is not an assignment', () {
    fixture.write(
      'packages/alpha/test/probe_test.dart',
      'void main() { if (goldenFileComparator == null) return; }\n',
    );

    expect(subjects(), isEmpty);
  });

  test('golden_baseline itself is exempt', () {
    fixture.member(
      'golden_baseline',
      files: {
        'test/golden_baseline_test.dart':
            'class X extends LocalFileComparator {}\n',
      },
    );

    expect(subjects(), isEmpty);
  });
}
