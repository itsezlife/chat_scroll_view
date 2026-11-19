/// Every test file of the package, run as one: one compile and one process
/// instead of one per file. `scripts/check` runs this file, and a new
/// `*_test.dart` is imported and grouped here (the workspace lints report
/// one that is not). Each file is a group of its own, so its `setUp` and
/// `tearDown` stay with its tests; the files share the process, so a test
/// that changes global state restores it.
library;

import 'package:test/test.dart';

import 'item/attach_item_test.dart' as attach_item_test;
import 'policy/attach_policy_test.dart' as attach_policy_test;
import 'selection/attach_selection_test.dart' as attach_selection_test;

void main() {
  group('item/attach_item_test.dart', attach_item_test.main);
  group('policy/attach_policy_test.dart', attach_policy_test.main);
  group('selection/attach_selection_test.dart', attach_selection_test.main);
}
