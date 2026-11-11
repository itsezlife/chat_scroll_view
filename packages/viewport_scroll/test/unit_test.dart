import 'package:flutter_test/flutter_test.dart';

import 'stretch_overscroll_test.dart' as stretch_overscroll_test;
import 'viewport_scroll_keys_test.dart' as viewport_scroll_keys_test;
import 'viewport_scroll_motion_test.dart' as viewport_scroll_motion_test;
import 'viewport_scroll_physics_test.dart' as viewport_scroll_physics_test;
import 'viewport_scroll_router_test.dart' as viewport_scroll_router_test;

void main() {
  group('stretch_overscroll_test.dart', stretch_overscroll_test.main);
  group('viewport_scroll_keys_test.dart', viewport_scroll_keys_test.main);
  group('viewport_scroll_motion_test.dart', viewport_scroll_motion_test.main);
  group('viewport_scroll_physics_test.dart', viewport_scroll_physics_test.main);
  group('viewport_scroll_router_test.dart', viewport_scroll_router_test.main);
}
