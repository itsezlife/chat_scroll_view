/// Gates behind `scripts/check`: workspace loading, the dependency-direction,
/// re-export, fakes-in-production and pure-Dart lints, and the per-member
/// analyze / test plan.
library;

export 'src/check_plan.dart';
export 'src/dependency_lint.dart';
export 'src/fakes_lint.dart';
export 'src/legacy_baseline.dart';
export 'src/library_file.dart';
export 'src/pure_dart_lint.dart';
export 'src/reexport_lint.dart';
export 'src/violation.dart';
export 'src/workspace.dart';
