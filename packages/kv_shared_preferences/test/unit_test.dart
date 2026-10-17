/// Every test file of the package, run as one: one compile and one process
/// instead of one per file. `scripts/check` runs this file, and a new
/// `*_test.dart` is imported and grouped here (the workspace lints report
/// one that is not). Each file is a group of its own, so its `setUp` and
/// `tearDown` stay with its tests; the files share the process, so a test
/// that changes global state restores it.
library;

import 'package:flutter_test/flutter_test.dart';

import 'shared_preferences_key_value_store_test.dart'
    as shared_preferences_key_value_store_test;

void main() {
  group(
    'shared_preferences_key_value_store_test.dart',
    shared_preferences_key_value_store_test.main,
  );
}
