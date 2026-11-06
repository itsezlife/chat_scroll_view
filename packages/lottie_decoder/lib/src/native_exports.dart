// The part of the public API that needs `dart:ffi`, `dart:io` or
// `dart:isolate`. The barrel exports this file by default and swaps in the
// stub where `dart.library.js_interop` is true (the web), so a web build
// never reaches one of those imports.
export 'package:lottie_decoder/src/cache/frame_cache_files_io.dart'
    show DirectoryFrameCacheFiles;
export 'package:lottie_decoder/src/engine/in_process_lottie_engine.dart';
export 'package:lottie_decoder/src/engine/isolate_lottie_engine.dart';
export 'package:lottie_decoder/src/engine/lottie_slot_engine.dart';
export 'package:lottie_decoder/src/memory/native_frame_page_memory.dart';
export 'package:lottie_decoder/src/renderer/lottie_frame_renderer.dart';
