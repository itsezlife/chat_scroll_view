/// Every test file of the package, run as one: one compile and one process
/// instead of one per file. `scripts/check` runs this file, and a new
/// `*_test.dart` is imported and grouped here (the workspace lints report
/// one that is not).
library;

import 'package:flutter_test/flutter_test.dart';

import 'native_frame_page_memory_test.dart' as native_frame_page_memory_test;

void main() {
  group(
    'native_frame_page_memory_test.dart',
    native_frame_page_memory_test.main,
  );
}
