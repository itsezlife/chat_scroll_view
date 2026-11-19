/// Every test file of the package, run as one: one compile and one process
/// instead of one per file. `scripts/check` runs this file, and a new
/// `*_test.dart` is imported and grouped here (the workspace lints report
/// one that is not). Each file is a group of its own, so its `setUp` and
/// `tearDown` stay with its tests; the files share the process, so a test
/// that changes global state restores it.
library;

import 'package:flutter_test/flutter_test.dart';

import 'page/attach_page_test.dart' as attach_page_test;
import 'page/attach_tab_bar_test.dart' as attach_tab_bar_test;
import 'policy/attach_sheet_policy_test.dart' as attach_sheet_policy_test;
import 'sheet/attach_sheet_android_test.dart' as attach_sheet_android_test;
import 'sheet/attach_sheet_golden_test.dart' as attach_sheet_golden_test;
import 'sheet/attach_sheet_ios_test.dart' as attach_sheet_ios_test;
import 'sheet/attach_sheet_morph_test.dart' as attach_sheet_morph_test;

void main() {
  group('page/attach_page_test.dart', attach_page_test.main);
  group('page/attach_tab_bar_test.dart', attach_tab_bar_test.main);
  group('policy/attach_sheet_policy_test.dart', attach_sheet_policy_test.main);
  group('sheet/attach_sheet_android_test.dart', attach_sheet_android_test.main);
  group('sheet/attach_sheet_golden_test.dart', attach_sheet_golden_test.main);
  group('sheet/attach_sheet_ios_test.dart', attach_sheet_ios_test.main);
  group('sheet/attach_sheet_morph_test.dart', attach_sheet_morph_test.main);
}
