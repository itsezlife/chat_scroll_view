/// The Lottie decoder adapter for the frame pool.
///
/// What compiles everywhere: the decoder, the engine interface that returns
/// pixels, the scheduler and the paintables, the pixel-copy renderer and the
/// frame cache (memory only on the web). What needs `dart:ffi`, `dart:io` or
/// `dart:isolate` (the slot engines that write to native memory by address,
/// native page memory, the zero-copy renderer, the cache's directory files)
/// is exported only where they exist. The browser worker lives in
/// `package:lottie_decoder/web.dart`, which only a web build imports.
library;

export 'src/cache/cached_frame.dart';
export 'src/cache/frame_cache.dart';
export 'src/cache/frame_cache_files.dart';
export 'src/cache/frame_cache_key.dart';
export 'src/decoder/lottie_decoder.dart';
export 'src/engine/lottie_engine.dart';
export 'src/engine/lottie_worker_port.dart';
export 'src/engine/web_worker_lottie_engine.dart'
    show LottieWorkerError, WebWorkerLottieEngine;
// The VM half is the default and the JS half the exception: the analyzer
// resolves a conditional export to its default URI, so the default must be
// the file that holds the native API. `dart.library.js_interop` is true on
// every web compiler (dart2js and dart2wasm) and false on the VM.
export 'src/environment_specific/native_exports_vm.dart'
    if (dart.library.js_interop) 'src/environment_specific/native_exports_js.dart';
export 'src/paint/lottie_animation_paintable.dart';
export 'src/paint/lottie_still_paintable.dart';
export 'src/playback/lottie_frame_scheduler.dart';
export 'src/renderer/lottie_frame_size.dart';
export 'src/renderer/lottie_source.dart';
export 'src/renderer/pixel_copy_frame_renderer.dart';
