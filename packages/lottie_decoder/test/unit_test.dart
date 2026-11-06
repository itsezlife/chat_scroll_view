/// Every test file of the package, run as one: one compile and one process
/// instead of one per file. `scripts/check` runs this file, and a new
/// `*_test.dart` is imported and grouped here (the workspace lints report
/// one that is not).
library;

import 'package:flutter_test/flutter_test.dart';

import 'in_process_lottie_engine_test.dart' as in_process_lottie_engine_test;
import 'lottie_frame_renderer_test.dart' as lottie_frame_renderer_test;
import 'native_frame_page_memory_test.dart' as native_frame_page_memory_test;
import 'paint/lottie_paintable_test.dart' as lottie_paintable_test;
import 'playback/lottie_frame_scheduler_test.dart'
    as lottie_frame_scheduler_test;

void main() {
  group('paint/lottie_paintable_test.dart', lottie_paintable_test.main);
  group(
    'playback/lottie_frame_scheduler_test.dart',
    lottie_frame_scheduler_test.main,
  );
  group(
    'in_process_lottie_engine_test.dart',
    in_process_lottie_engine_test.main,
  );
  group('lottie_frame_renderer_test.dart', lottie_frame_renderer_test.main);
  group(
    'native_frame_page_memory_test.dart',
    native_frame_page_memory_test.main,
  );
}
