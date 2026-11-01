/// Every test file of the package, run as one: one compile and one process
/// instead of one per file. `scripts/check` runs this file, and a new
/// `*_test.dart` is imported and grouped here (the workspace lints report
/// one that is not). Each file is a group of its own, so its `setUp` and
/// `tearDown` stay with its tests; the files share the process, so a test
/// that changes global state restores it.
library;

import 'package:flutter_test/flutter_test.dart';

import 'src/codec/chat_wallpaper_codec_test.dart' as chat_wallpaper_codec_test;
import 'src/model/chat_wallpaper_test.dart' as chat_wallpaper_test;
import 'src/model/wallpaper_service_shade_test.dart'
    as wallpaper_service_shade_test;
import 'src/model/wallpaper_service_tone_test.dart'
    as wallpaper_service_tone_test;
import 'src/motion/chat_wallpaper_motion_controller_test.dart'
    as chat_wallpaper_motion_controller_test;
import 'src/motion/chat_wallpaper_motion_scope_test.dart'
    as chat_wallpaper_motion_scope_test;
import 'src/motion/freeform_keyframes_test.dart' as freeform_keyframes_test;
import 'src/render/freeform_gradient_test.dart' as freeform_gradient_test;
import 'src/render/wallpaper_pattern_image_test.dart'
    as wallpaper_pattern_image_test;
import 'src/widget/chat_wallpaper_surface_test.dart'
    as chat_wallpaper_surface_test;
import 'src/widget/chat_wallpaper_theme_test.dart' as chat_wallpaper_theme_test;
import 'src/widget/chat_wallpaper_view_pattern_test.dart'
    as chat_wallpaper_view_pattern_test;
import 'src/widget/chat_wallpaper_view_test.dart' as chat_wallpaper_view_test;
import 'src/widget/chat_wallpaper_warm_up_test.dart'
    as chat_wallpaper_warm_up_test;
import 'src/widget/pattern_resize_test.dart' as pattern_resize_test;

void main() {
  group(
    'src/codec/chat_wallpaper_codec_test.dart',
    chat_wallpaper_codec_test.main,
  );
  group('src/model/chat_wallpaper_test.dart', chat_wallpaper_test.main);
  group(
    'src/model/wallpaper_service_shade_test.dart',
    wallpaper_service_shade_test.main,
  );
  group(
    'src/model/wallpaper_service_tone_test.dart',
    wallpaper_service_tone_test.main,
  );
  group(
    'src/motion/chat_wallpaper_motion_controller_test.dart',
    chat_wallpaper_motion_controller_test.main,
  );
  group(
    'src/motion/chat_wallpaper_motion_scope_test.dart',
    chat_wallpaper_motion_scope_test.main,
  );
  group(
    'src/motion/freeform_keyframes_test.dart',
    freeform_keyframes_test.main,
  );
  group('src/render/freeform_gradient_test.dart', freeform_gradient_test.main);
  group(
    'src/render/wallpaper_pattern_image_test.dart',
    wallpaper_pattern_image_test.main,
  );
  group(
    'src/widget/chat_wallpaper_surface_test.dart',
    chat_wallpaper_surface_test.main,
  );
  group(
    'src/widget/chat_wallpaper_theme_test.dart',
    chat_wallpaper_theme_test.main,
  );
  group(
    'src/widget/chat_wallpaper_view_pattern_test.dart',
    chat_wallpaper_view_pattern_test.main,
  );
  group(
    'src/widget/chat_wallpaper_view_test.dart',
    chat_wallpaper_view_test.main,
  );
  group(
    'src/widget/chat_wallpaper_warm_up_test.dart',
    chat_wallpaper_warm_up_test.main,
  );
  group('src/widget/pattern_resize_test.dart', pattern_resize_test.main);
}
