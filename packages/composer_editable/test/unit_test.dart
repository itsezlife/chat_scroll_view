/// Every test file of the package, run as one: one compile and one process
/// instead of one per file. `scripts/check` runs this file, and a new
/// `*_test.dart` is imported and grouped here (the workspace lints report
/// one that is not). Each file is a group of its own, so its `setUp` and
/// `tearDown` stay with its tests; the files share the process, so a test
/// that changes global state restores it.
library;

import 'package:flutter_test/flutter_test.dart';

import 'finger_tracked_handle_test.dart' as finger_tracked_handle_test;
import 'nested_overscroll_handoff_test.dart' as nested_overscroll_handoff_test;
import 'select_all_page_scroll_test.dart' as select_all_page_scroll_test;
import 'selection_drag_snap_test.dart' as selection_drag_snap_test;
import 'selection_handle_motion_test.dart' as selection_handle_motion_test;
import 'universal_field_gestures_test.dart' as universal_field_gestures_test;

void main() {
  group('finger_tracked_handle_test.dart', finger_tracked_handle_test.main);
  group(
    'nested_overscroll_handoff_test.dart',
    nested_overscroll_handoff_test.main,
  );
  group('select_all_page_scroll_test.dart', select_all_page_scroll_test.main);
  group('selection_drag_snap_test.dart', selection_drag_snap_test.main);
  group(
    'selection_handle_motion_test.dart',
    selection_handle_motion_test.main,
  );
  group(
    'universal_field_gestures_test.dart',
    universal_field_gestures_test.main,
  );
}
