/// Every test file of the package, run as one: one compile and one process
/// instead of one per file. `scripts/check` runs this file, and a new
/// `*_test.dart` is imported and grouped here (the workspace lints report
/// one that is not). Each file is a group of its own, so its `setUp` and
/// `tearDown` stay with its tests; the files share the process, so a test
/// that changes global state restores it.
library;

import 'package:test/test.dart';

import 'bench_baseline_store_test.dart' as bench_baseline_store_test;
import 'bench_compare_test.dart' as bench_compare_test;
import 'check_plan_test.dart' as check_plan_test;
import 'check_runner_test.dart' as check_runner_test;
import 'dependency_lint_test.dart' as dependency_lint_test;
import 'fakes_lint_test.dart' as fakes_lint_test;
import 'legacy_baseline_test.dart' as legacy_baseline_test;
import 'library_file_test.dart' as library_file_test;
import 'pure_dart_lint_test.dart' as pure_dart_lint_test;
import 'reexport_lint_test.dart' as reexport_lint_test;
import 'test_entrypoint_lint_test.dart' as test_entrypoint_lint_test;
import 'workspace_graph_test.dart' as workspace_graph_test;

void main() {
  group('bench_baseline_store_test.dart', bench_baseline_store_test.main);
  group('bench_compare_test.dart', bench_compare_test.main);
  group('check_plan_test.dart', check_plan_test.main);
  group('check_runner_test.dart', check_runner_test.main);
  group('dependency_lint_test.dart', dependency_lint_test.main);
  group('fakes_lint_test.dart', fakes_lint_test.main);
  group('legacy_baseline_test.dart', legacy_baseline_test.main);
  group('library_file_test.dart', library_file_test.main);
  group('pure_dart_lint_test.dart', pure_dart_lint_test.main);
  group('reexport_lint_test.dart', reexport_lint_test.main);
  group('test_entrypoint_lint_test.dart', test_entrypoint_lint_test.main);
  group('workspace_graph_test.dart', workspace_graph_test.main);
}
