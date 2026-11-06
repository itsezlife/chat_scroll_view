/// The video decoder adapter: the `Decoder` of the video media form, the
/// scheduler that plays clips, the engine seam and its engines.
///
/// What compiles everywhere: the decoder, the `VideoEngine` seam with its
/// clip, result and error types, the scheduler, the paintables, the video
/// frame pool and its renderer. The engines that decode through a native
/// binding (in process, and a pool of worker isolates) need `dart:ffi` and
/// `dart:isolate` and are exported only where they exist.
library;

export 'src/decoder/video_decoder.dart';
export 'src/engine/video_element_port.dart';
export 'src/engine/video_engine.dart';
// The native file is the default and the stub the exception because the
// analyzer resolves a conditional export to its default URI and ignores
// `dart.library.js_interop`. That condition is true on every web compiler and
// false on the VM.
export 'src/engine/web_video_engine.dart';
export 'src/native_exports.dart'
    if (dart.library.js_interop) 'src/native_exports_stub.dart';
export 'src/paint/video_animation_paintable.dart';
export 'src/paint/video_still_paintable.dart';
export 'src/playback/video_frame_scheduler.dart';
export 'src/renderer/video_frame_atlas.dart';
export 'src/renderer/video_frame_renderer.dart';
export 'src/renderer/video_frame_size.dart';
export 'src/renderer/video_frame_source.dart';
