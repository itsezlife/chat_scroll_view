/// Every test file of the package, run as one: `scripts/check` runs this
/// file, and a new `*_test.dart` is imported and grouped here.
library;

import 'package:flutter_test/flutter_test.dart';

import 'golden_baseline_test.dart' as golden_baseline_test;

void main() {
  group('golden_baseline_test.dart', golden_baseline_test.main);
}
