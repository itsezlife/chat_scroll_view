/// Every test file of the package, run as one: one compile and one process
/// instead of one per file. `scripts/check` runs this file, and a new
/// `*_test.dart` is imported and grouped here (the workspace lints report
/// one that is not). Each file is a group of its own, so its `setUp` and
/// `tearDown` stay with its tests; the files share the process, so a test
/// that changes global state restores it.
library;

import 'package:flutter_test/flutter_test.dart';

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
import 'paint/message_media_view_test.dart' as paint_message_media_view_test;
import 'policy/desktop_mosaic_algorithm_test.dart'
    as policy_desktop_mosaic_algorithm_test;
import 'policy/media_box_sizing_test.dart' as policy_media_box_sizing_test;
import 'policy/media_corner_policy_test.dart'
    as policy_media_corner_policy_test;
import 'policy/media_layout_policy_test.dart'
    as policy_media_layout_policy_test;
import 'policy/message_media_policy_test.dart'
    as policy_message_media_policy_test;
import 'single_media_layout_test.dart' as single_media_layout_test;

void main() {
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
  group('paint/message_media_view_test', paint_message_media_view_test.main);
  group(
    'policy/desktop_mosaic_algorithm_test',
    policy_desktop_mosaic_algorithm_test.main,
  );
  group('policy/media_box_sizing_test', policy_media_box_sizing_test.main);
  group(
    'policy/media_corner_policy_test',
    policy_media_corner_policy_test.main,
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
}
