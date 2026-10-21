/// Every test file of the package, run as one: one compile and one process
/// instead of one per file. `scripts/check` runs this file, and a new
/// `*_test.dart` is imported and grouped here (the workspace lints report
/// one that is not). Each file is a group of its own, so its `setUp` and
/// `tearDown` stay with its tests; the files share the process, so a test
/// that changes global state restores it.
library;

import 'package:flutter_test/flutter_test.dart';

import 'controller/panel_shell_controller_test.dart'
    as panel_shell_controller_test;
import 'event/panel_event_test.dart' as panel_event_test;
import 'goldens/panel_shell_golden_test.dart' as panel_shell_golden_test;
import 'page/panel_page_test.dart' as panel_page_test;
import 'scroll/bottom_bar_visibility_test.dart' as bottom_bar_visibility_test;
import 'search/debounced_search_test.dart' as debounced_search_test;
import 'testing/page_controller_registry_test.dart'
    as page_controller_registry_test;
import 'testing/panel_semantics_rule_test.dart' as panel_semantics_rule_test;
import 'widgets/panel_arrangement_test.dart' as panel_arrangement_test;
import 'widgets/panel_shell_pointer_test.dart' as panel_shell_pointer_test;
import 'widgets/panel_shell_test.dart' as panel_shell_test;

void main() {
  group(
    'controller/panel_shell_controller_test.dart',
    panel_shell_controller_test.main,
  );
  group('event/panel_event_test.dart', panel_event_test.main);
  group('goldens/panel_shell_golden_test.dart', panel_shell_golden_test.main);
  group('page/panel_page_test.dart', panel_page_test.main);
  group(
    'scroll/bottom_bar_visibility_test.dart',
    bottom_bar_visibility_test.main,
  );
  group('search/debounced_search_test.dart', debounced_search_test.main);
  group(
    'testing/page_controller_registry_test.dart',
    page_controller_registry_test.main,
  );
  group(
    'testing/panel_semantics_rule_test.dart',
    panel_semantics_rule_test.main,
  );
  group('widgets/panel_arrangement_test.dart', panel_arrangement_test.main);
  group('widgets/panel_shell_pointer_test.dart', panel_shell_pointer_test.main);
  group('widgets/panel_shell_test.dart', panel_shell_test.main);
}
