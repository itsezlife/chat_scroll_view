/// Gates behind `scripts/check`: workspace loading, the dependency-direction,
/// re-export, fakes-in-production and pure-Dart lints, and the per-member
/// analyze / test plan.
library;

export 'src/bench_baseline_store.dart';
export 'src/bench_compare.dart';
export 'src/bench_report.dart';
export 'src/check_plan.dart';
export 'src/dependency_lint.dart';
export 'src/fakes_lint.dart';
export 'src/legacy_baseline.dart';
export 'src/library_file.dart';
export 'src/library_scope_lint.dart';
export 'src/platform_fork_lint.dart';
export 'src/pure_dart_lint.dart';
export 'src/reexport_lint.dart';
export 'src/violation.dart';
export 'src/workspace.dart';
