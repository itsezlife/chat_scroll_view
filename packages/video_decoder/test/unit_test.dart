/// Every test file of the package, run as one: one compile and one process
/// instead of one per file. `scripts/check` runs this file, and a new
/// `*_test.dart` is imported and grouped here (the workspace lints report
/// one that is not).
library;

import 'package:flutter_test/flutter_test.dart';

import 'decoder/video_decoder_native_test.dart' as video_decoder_native_test;
import 'decoder/video_decoder_test.dart' as video_decoder_test;
import 'fake_video_engine_test.dart' as fake_video_engine_test;
import 'in_process_video_engine_native_test.dart'
    as in_process_video_engine_native_test;
import 'in_process_video_engine_test.dart' as in_process_video_engine_test;
import 'isolate_video_engine_native_test.dart'
    as isolate_video_engine_native_test;
import 'isolate_video_engine_test.dart' as isolate_video_engine_test;
import 'paint/video_animation_paintable_test.dart'
    as video_animation_paintable_test;
import 'playback/video_frame_scheduler_test.dart' as video_frame_scheduler_test;
import 'renderer/video_frame_size_test.dart' as video_frame_size_test;
import 'web/video_frame_pixels_test.dart' as video_frame_pixels_test;
import 'web/web_compile_test.dart' as web_compile_test;
import 'web/web_video_engine_test.dart' as web_video_engine_test;

void main() {
  group(
    'decoder/video_decoder_native_test.dart',
    video_decoder_native_test.main,
  );
  group('decoder/video_decoder_test.dart', video_decoder_test.main);
  group(
    'paint/video_animation_paintable_test.dart',
    video_animation_paintable_test.main,
  );
  group(
    'playback/video_frame_scheduler_test.dart',
    video_frame_scheduler_test.main,
  );
  group('renderer/video_frame_size_test.dart', video_frame_size_test.main);
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
  group('web/video_frame_pixels_test.dart', video_frame_pixels_test.main);
  group('web/web_compile_test.dart', web_compile_test.main);
  group('web/web_video_engine_test.dart', web_video_engine_test.main);
}
