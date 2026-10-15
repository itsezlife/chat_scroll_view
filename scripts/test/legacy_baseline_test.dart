import 'package:test/test.dart';
import 'package:workspace_check/workspace_check.dart';

void main() {
  const reexport = Violation(
    LintRule.crossPackageReexport,
    'packages/old/lib/old.dart exports package:neighbour/neighbour.dart',
  );
  const fakeExport = Violation(
    LintRule.fakeExportedOutsideTesting,
    'packages/old/lib/old.dart exports src/fake_old.dart',
  );
  const knownReexport = LegacyException(
    LintRule.crossPackageReexport,
    'packages/old/lib/old.dart exports package:neighbour/neighbour.dart',
    removedBy: 'issue 99',
  );

  test('passes violations nobody excused', () {
    expect(LegacyBaseline.apply([reexport, fakeExport], legacy: []), [
      reexport,
      fakeExport,
    ]);
  });

  test('drops a violation that matches an exception on rule and subject', () {
    expect(
      LegacyBaseline.apply([reexport, fakeExport], legacy: [knownReexport]),
      [fakeExport],
    );
  });

  test('an exception for a different rule does not excuse the violation', () {
    expect(
      LegacyBaseline.apply(
        [fakeExport],
        legacy: [
          const LegacyException(
            LintRule.crossPackageReexport,
            'packages/old/lib/old.dart exports src/fake_old.dart',
            removedBy: 'issue 99',
          ),
        ],
      ).map((v) => v.rule),
      [LintRule.fakeExportedOutsideTesting, LintRule.staleLegacyException],
    );
  });

  test('an exception that matches nothing is reported as stale', () {
    final remaining = LegacyBaseline.apply(const [], legacy: [knownReexport]);

    expect(remaining.map((v) => v.rule), [LintRule.staleLegacyException]);
    expect(
      remaining.single.subject,
      '${knownReexport.rule.name}: ${knownReexport.subject} (removed by issue 99)',
    );
  });

  test('each exception excuses only one violation, so duplicates surface', () {
    expect(
      LegacyBaseline.apply([reexport, reexport], legacy: [knownReexport]),
      [reexport],
    );
  });
}
