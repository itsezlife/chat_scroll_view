/// The Lottie decoder adapter for the frame pool.
///
/// What compiles everywhere: the decoder, the engine interface that returns
/// pixels, the scheduler and the paintables, the pixel-copy renderer and the
/// frame cache (memory only on the web). What needs `dart:ffi`, `dart:io` or
/// `dart:isolate` (the slot engines that write to native memory by address,
/// native page memory, the zero-copy renderer, the cache's directory files)
/// is exported only where they exist.
library;

export 'src/cache/frame_cache.dart';
export 'src/cache/frame_cache_files.dart';
export 'src/cache/frame_cache_key.dart';
export 'src/decoder/lottie_decoder.dart';
export 'src/engine/lottie_engine.dart';
// The native file is the default and the stub the exception because the
// analyzer resolves a conditional export to its default URI and ignores
// `dart.library.js_interop`: written the other way round, the analyzer sees no
// native API at all. `dart.library.js_interop` is true on every web compiler
// (dart2js and dart2wasm) and false on the VM, so the choice is the same as
// `dart.library.ffi` would make.
export 'src/native_exports.dart'
    if (dart.library.js_interop) 'src/native_exports_stub.dart';
export 'src/paint/lottie_animation_paintable.dart';
export 'src/paint/lottie_still_paintable.dart';
export 'src/playback/lottie_frame_scheduler.dart';
export 'src/renderer/lottie_frame_size.dart';
export 'src/renderer/lottie_source.dart';
export 'src/renderer/pixel_copy_frame_renderer.dart';
