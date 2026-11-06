/// Every test file of the package, run as one: one compile and one process
/// instead of one per file. `scripts/check` runs this file, and a new
/// `*_test.dart` is imported and grouped here (the workspace lints report
/// one that is not).
library;

import 'package:flutter_test/flutter_test.dart';

import 'benchmark/lottie_playback_bench_test.dart'
    as lottie_playback_bench_test;
import 'cache/frame_cache_key_test.dart' as frame_cache_key_test;
import 'cache/frame_cache_test.dart' as frame_cache_test;
import 'in_process_lottie_engine_test.dart' as in_process_lottie_engine_test;
import 'isolate_lottie_engine_test.dart' as isolate_lottie_engine_test;
import 'lottie_decoder_pixel_engine_test.dart'
    as lottie_decoder_pixel_engine_test;
import 'lottie_decoder_test.dart' as lottie_decoder_test;
import 'lottie_frame_renderer_test.dart' as lottie_frame_renderer_test;
import 'lottie_frame_size_test.dart' as lottie_frame_size_test;
import 'native_frame_page_memory_test.dart' as native_frame_page_memory_test;
import 'paint/lottie_paintable_test.dart' as lottie_paintable_test;
import 'playback/lottie_frame_scheduler_test.dart'
    as lottie_frame_scheduler_test;
import 'renderer/lottie_source_test.dart' as lottie_source_test;
import 'renderer/pixel_copy_frame_renderer_test.dart'
    as pixel_copy_frame_renderer_test;
import 'testing/fake_pixel_lottie_engine_test.dart'
    as fake_pixel_lottie_engine_test;

void main() {
  group(
    'benchmark/lottie_playback_bench_test.dart',
    lottie_playback_bench_test.main,
  );
  group('cache/frame_cache_key_test.dart', frame_cache_key_test.main);
  group('cache/frame_cache_test.dart', frame_cache_test.main);
  group('paint/lottie_paintable_test.dart', lottie_paintable_test.main);
  group(
    'playback/lottie_frame_scheduler_test.dart',
    lottie_frame_scheduler_test.main,
  );
  group('renderer/lottie_source_test.dart', lottie_source_test.main);
  group(
    'renderer/pixel_copy_frame_renderer_test.dart',
    pixel_copy_frame_renderer_test.main,
  );
  group(
    'testing/fake_pixel_lottie_engine_test.dart',
    fake_pixel_lottie_engine_test.main,
  );
  group(
    'in_process_lottie_engine_test.dart',
    in_process_lottie_engine_test.main,
  );
  group('isolate_lottie_engine_test.dart', isolate_lottie_engine_test.main);
  group(
    'lottie_decoder_pixel_engine_test.dart',
    lottie_decoder_pixel_engine_test.main,
  );
  group('lottie_decoder_test.dart', lottie_decoder_test.main);
  group('lottie_frame_renderer_test.dart', lottie_frame_renderer_test.main);
  group('lottie_frame_size_test.dart', lottie_frame_size_test.main);
  group(
    'native_frame_page_memory_test.dart',
    native_frame_page_memory_test.main,
  );
}
