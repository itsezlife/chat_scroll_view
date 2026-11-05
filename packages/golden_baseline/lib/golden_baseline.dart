/// Test support for golden tests: baselines belong to one host, the CI
/// runner, and are compared and regenerated only there.
///
/// A golden test calls [useGoldenBaselines] once in its `main`:
///
/// ```dart
/// void main() {
///   useGoldenBaselines('test/goldens/rows_golden_test.dart');
///   testWidgets('a row', (tester) async { ... });
/// }
/// ```
library;

export 'src/golden_baseline.dart';
