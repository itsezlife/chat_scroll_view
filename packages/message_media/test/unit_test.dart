/// Every test file of the package, run as one: one compile and one process
/// instead of one per file. `scripts/check` runs this file, and a new
/// `*_test.dart` is imported and grouped here (the workspace lints report
/// one that is not). Each file is a group of its own, so its `setUp` and
/// `tearDown` stay with its tests; the files share the process, so a test
/// that changes global state restores it.
library;

import 'package:flutter_test/flutter_test.dart';

import 'bubble/media_bubble_composition_test.dart'
    as bubble_media_bubble_composition_test;
import 'bubble/message_media_bubble_layout_test.dart'
    as bubble_message_media_bubble_layout_test;
import 'chrome/media_cell_chrome_test.dart' as chrome_media_cell_chrome_test;
import 'chrome/media_chrome_rules_test.dart' as chrome_media_chrome_rules_test;
import 'diagnostics/media_trace_test.dart' as diagnostics_media_trace_test;
import 'gesture/media_gesture_rules_test.dart'
    as gesture_media_gesture_rules_test;
import 'gesture/media_gestures_test.dart' as gesture_media_gestures_test;
import 'goldens/media_geometry_golden_test.dart'
    as goldens_media_geometry_golden_test;
import 'goldens/message_media_view_golden_test.dart'
    as goldens_message_media_view_golden_test;
import 'grouped_messages_calculate_test.dart'
    as grouped_messages_calculate_test;
import 'media_item_keying_test.dart' as media_item_keying_test;
import 'message_media_hit_part_test.dart' as message_media_hit_part_test;
import 'message_media_state_test.dart' as message_media_state_test;
import 'mosaic_layout_test.dart' as mosaic_layout_test;
import 'outgoing/media_outgoing_test.dart' as outgoing_media_outgoing_test;
import 'paint/link_preview_card_test.dart' as paint_link_preview_card_test;
import 'paint/media_row_cell_test.dart' as paint_media_row_cell_test;
import 'paint/message_media_view_test.dart' as paint_message_media_view_test;
import 'policy/desktop_mosaic_algorithm_test.dart'
    as policy_desktop_mosaic_algorithm_test;
import 'policy/ios_mosaic_algorithm_test.dart'
    as policy_ios_mosaic_algorithm_test;
import 'policy/link_preview_card_policy_test.dart'
    as policy_link_preview_card_policy_test;
import 'policy/media_box_sizing_test.dart' as policy_media_box_sizing_test;
import 'policy/media_corner_policy_test.dart'
    as policy_media_corner_policy_test;
import 'policy/media_file_stack_policy_test.dart'
    as policy_media_file_stack_policy_test;
import 'policy/media_layout_policy_test.dart'
    as policy_media_layout_policy_test;
import 'policy/message_media_policy_test.dart'
    as policy_message_media_policy_test;
import 'single_media_layout_test.dart' as single_media_layout_test;
import 'transition/media_layout_lerp_test.dart'
    as transition_media_layout_lerp_test;
import 'transition/media_layout_transition_test.dart'
    as transition_media_layout_transition_test;
import 'transition/message_media_transition_test.dart'
    as transition_message_media_transition_test;

void main() {
  group(
    'bubble/media_bubble_composition_test',
    bubble_media_bubble_composition_test.main,
  );
  group(
    'bubble/message_media_bubble_layout_test',
    bubble_message_media_bubble_layout_test.main,
  );
  group('chrome/media_cell_chrome_test', chrome_media_cell_chrome_test.main);
  group('chrome/media_chrome_rules_test', chrome_media_chrome_rules_test.main);
  group('diagnostics/media_trace_test', diagnostics_media_trace_test.main);
  group(
    'gesture/media_gesture_rules_test',
    gesture_media_gesture_rules_test.main,
  );
  group('gesture/media_gestures_test', gesture_media_gestures_test.main);
  group(
    'goldens/media_geometry_golden_test',
    goldens_media_geometry_golden_test.main,
  );
  group(
    'goldens/message_media_view_golden_test',
    goldens_message_media_view_golden_test.main,
  );
  group(
    'grouped_messages_calculate_test',
    grouped_messages_calculate_test.main,
  );
  group('media_item_keying_test', media_item_keying_test.main);
  group('message_media_hit_part_test', message_media_hit_part_test.main);
  group('message_media_state_test', message_media_state_test.main);
  group('mosaic_layout_test', mosaic_layout_test.main);
  group('outgoing/media_outgoing_test', outgoing_media_outgoing_test.main);
  group('paint/link_preview_card_test', paint_link_preview_card_test.main);
  group('paint/media_row_cell_test', paint_media_row_cell_test.main);
  group('paint/message_media_view_test', paint_message_media_view_test.main);
  group(
    'policy/desktop_mosaic_algorithm_test',
    policy_desktop_mosaic_algorithm_test.main,
  );
  group(
    'policy/ios_mosaic_algorithm_test',
    policy_ios_mosaic_algorithm_test.main,
  );
  group('policy/media_box_sizing_test', policy_media_box_sizing_test.main);
  group(
    'policy/media_corner_policy_test',
    policy_media_corner_policy_test.main,
  );
  group(
    'policy/link_preview_card_policy_test',
    policy_link_preview_card_policy_test.main,
  );
  group(
    'policy/media_file_stack_policy_test',
    policy_media_file_stack_policy_test.main,
  );
  group(
    'policy/media_layout_policy_test',
    policy_media_layout_policy_test.main,
  );
  group(
    'policy/message_media_policy_test',
    policy_message_media_policy_test.main,
  );
  group('single_media_layout_test', single_media_layout_test.main);
  group(
    'transition/media_layout_lerp_test',
    transition_media_layout_lerp_test.main,
  );
  group(
    'transition/media_layout_transition_test',
    transition_media_layout_transition_test.main,
  );
  group(
    'transition/message_media_transition_test',
    transition_message_media_transition_test.main,
  );
}
