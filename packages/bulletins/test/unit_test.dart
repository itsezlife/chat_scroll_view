/// Every test file of the package, run as one: one compile and one process
/// instead of one per file. `scripts/check` runs this file, and a new
/// `*_test.dart` is imported and grouped here (the workspace lints report
/// one that is not). Each file is a group of its own, so its `setUp` and
/// `tearDown` stay with its tests; the files share the process, so a test
/// that changes global state restores it.
library;

import 'package:flutter_test/flutter_test.dart';

import 'android/bulletin_android_golden_test.dart'
    as bulletin_android_golden_test;
import 'android/bulletin_android_motion_test.dart'
    as bulletin_android_motion_test;
import 'android/bulletin_builders_android_test.dart'
    as bulletin_builders_android_test;
import 'bulletin/bulletin_test.dart' as bulletin_test;
import 'controller/bulletin_controller_test.dart' as bulletin_controller_test;
import 'desktop/desktop_toast_golden_test.dart' as desktop_toast_golden_test;
import 'desktop/desktop_toast_test.dart' as desktop_toast_test;
import 'ios/bulletin_ios_golden_test.dart' as bulletin_ios_golden_test;
import 'ios/bulletin_ios_test.dart' as bulletin_ios_test;
import 'policy/bulletin_policy_test.dart' as bulletin_policy_test;
import 'view/bulletin_host_test.dart' as bulletin_host_test;
import 'view/bulletin_message_test.dart' as bulletin_message_test;

void main() {
  group(
    'android/bulletin_android_golden_test.dart',
    bulletin_android_golden_test.main,
  );
  group(
    'android/bulletin_android_motion_test.dart',
    bulletin_android_motion_test.main,
  );
  group(
    'android/bulletin_builders_android_test.dart',
    bulletin_builders_android_test.main,
  );
  group('bulletin/bulletin_test.dart', bulletin_test.main);
  group(
    'controller/bulletin_controller_test.dart',
    bulletin_controller_test.main,
  );
  group(
    'desktop/desktop_toast_golden_test.dart',
    desktop_toast_golden_test.main,
  );
  group('desktop/desktop_toast_test.dart', desktop_toast_test.main);
  group('ios/bulletin_ios_golden_test.dart', bulletin_ios_golden_test.main);
  group('ios/bulletin_ios_test.dart', bulletin_ios_test.main);
  group('policy/bulletin_policy_test.dart', bulletin_policy_test.main);
  group('view/bulletin_host_test.dart', bulletin_host_test.main);
  group('view/bulletin_message_test.dart', bulletin_message_test.main);
}
