/// Every test file of the package, run as one: one compile and one process
/// instead of one per file. `scripts/check` runs this file, and a new
/// `*_test.dart` is imported and grouped here (the workspace lints report
/// one that is not).
library;

import 'package:flutter_test/flutter_test.dart';

import 'barrel_native_exports_test.dart' as barrel_native_exports_test;
import 'chat_video_status_test.dart' as chat_video_status_test;
import 'fake_video_binding_contract_test.dart'
    as fake_video_binding_contract_test;
import 'hook_build_test.dart' as hook_build_test;
import 'native_video_binding_contract_test.dart'
    as native_video_binding_contract_test;
import 'native_video_binding_probe_test.dart'
    as native_video_binding_probe_test;
import 'native_video_binding_test.dart' as native_video_binding_test;

void main() {
  group('barrel_native_exports_test.dart', barrel_native_exports_test.main);
  group('chat_video_status_test.dart', chat_video_status_test.main);
  group(
    'fake_video_binding_contract_test.dart',
    fake_video_binding_contract_test.main,
  );
  group('hook_build_test.dart', hook_build_test.main);
  group(
    'native_video_binding_contract_test.dart',
    native_video_binding_contract_test.main,
  );
  group(
    'native_video_binding_probe_test.dart',
    native_video_binding_probe_test.main,
  );
  group('native_video_binding_test.dart', native_video_binding_test.main);
}
