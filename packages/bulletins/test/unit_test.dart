/// Every test file of the package, run as one: one compile and one process
/// instead of one per file. `scripts/check` runs this file, and a new
/// `*_test.dart` is imported and grouped here (the workspace lints report
/// one that is not). Each file is a group of its own, so its `setUp` and
/// `tearDown` stay with its tests; the files share the process, so a test
/// that changes global state restores it.
library;

import 'package:flutter_test/flutter_test.dart';

import 'bulletin/bulletin_test.dart' as bulletin_test;
import 'policy/bulletin_policy_test.dart' as bulletin_policy_test;

void main() {
  group('bulletin/bulletin_test.dart', bulletin_test.main);
  group('policy/bulletin_policy_test.dart', bulletin_policy_test.main);
}
