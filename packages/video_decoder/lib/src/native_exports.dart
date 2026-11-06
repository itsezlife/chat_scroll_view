// The part of the public API that needs `dart:ffi` or `dart:isolate`. The
// barrel exports this file by default and swaps in the stub where
// `dart.library.js_interop` is true (the web).
export 'package:video_decoder/src/engine/in_process_video_engine.dart';
