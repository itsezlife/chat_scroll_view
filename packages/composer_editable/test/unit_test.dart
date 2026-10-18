/// Every test file of the package, run as one: one compile and one process
/// instead of one per file. `scripts/check` runs this file, and a new
/// `*_test.dart` is imported and grouped here (the workspace lints report
/// one that is not). Each file is a group of its own, so its `setUp` and
/// `tearDown` stay with its tests; the files share the process, so a test
/// that changes global state restores it.
library;

import 'package:flutter_test/flutter_test.dart';

import 'android_spell_check_test.dart' as android_spell_check_test;
import 'content_scroll_padding_test.dart' as content_scroll_padding_test;
import 'exported_names_test.dart' as exported_names_test;
import 'finger_tracked_handle_test.dart' as finger_tracked_handle_test;
import 'ios_restored_paths_test.dart' as ios_restored_paths_test;
import 'nested_overscroll_handoff_test.dart' as nested_overscroll_handoff_test;
import 'release_parity_test.dart' as release_parity_test;
import 'revendor_test.dart' as revendor_test;
import 'select_all_page_scroll_test.dart' as select_all_page_scroll_test;
import 'selection_drag_snap_test.dart' as selection_drag_snap_test;
import 'selection_handle_motion_test.dart' as selection_handle_motion_test;
import 'selection_highlight_gapless_test.dart'
    as selection_highlight_gapless_test;
import 'selection_highlight_golden_test.dart'
    as selection_highlight_golden_test;
import 'toolbar_fade_test.dart' as toolbar_fade_test;
import 'universal_field_gestures_test.dart' as universal_field_gestures_test;

void main() {
  group('android_spell_check_test.dart', android_spell_check_test.main);
  group('content_scroll_padding_test.dart', content_scroll_padding_test.main);
  group('exported_names_test.dart', exported_names_test.main);
  group('finger_tracked_handle_test.dart', finger_tracked_handle_test.main);
  group('ios_restored_paths_test.dart', ios_restored_paths_test.main);
  group(
    'nested_overscroll_handoff_test.dart',
    nested_overscroll_handoff_test.main,
  );
  group('release_parity_test.dart', release_parity_test.main);
  group('revendor_test.dart', revendor_test.main);
  group('select_all_page_scroll_test.dart', select_all_page_scroll_test.main);
  group('selection_drag_snap_test.dart', selection_drag_snap_test.main);
  group('selection_handle_motion_test.dart', selection_handle_motion_test.main);
  group(
    'selection_highlight_gapless_test.dart',
    selection_highlight_gapless_test.main,
  );
  group(
    'selection_highlight_golden_test.dart',
    selection_highlight_golden_test.main,
  );
  group('toolbar_fade_test.dart', toolbar_fade_test.main);
  group(
    'universal_field_gestures_test.dart',
    universal_field_gestures_test.main,
  );
}
