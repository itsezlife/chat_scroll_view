/// Every test file of the package, run as one: one compile and one process
/// instead of one per file. `scripts/check` runs this file, and a new
/// `*_test.dart` is imported and grouped here (the workspace lints report
/// one that is not).
library;

import 'package:flutter_test/flutter_test.dart';

import 'fake_video_engine_test.dart' as fake_video_engine_test;
import 'in_process_video_engine_native_test.dart'
    as in_process_video_engine_native_test;
import 'in_process_video_engine_test.dart' as in_process_video_engine_test;
import 'isolate_video_engine_native_test.dart'
    as isolate_video_engine_native_test;
import 'isolate_video_engine_test.dart' as isolate_video_engine_test;

void main() {
  group('fake_video_engine_test.dart', fake_video_engine_test.main);
  group(
    'in_process_video_engine_native_test.dart',
    in_process_video_engine_native_test.main,
  );
  group('in_process_video_engine_test.dart', in_process_video_engine_test.main);
  group(
    'isolate_video_engine_native_test.dart',
    isolate_video_engine_native_test.main,
  );
  group('isolate_video_engine_test.dart', isolate_video_engine_test.main);
}
