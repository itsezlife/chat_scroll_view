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
export 'src/engine/web_video_engine.dart';
// The VM half is the default and the JS half the exception: the analyzer
// resolves a conditional export to its default URI, so the default must be
// the file that holds the native engines. `dart.library.js_interop` is true on
// every web compiler and false on the VM.
export 'src/environment_specific/native_exports_vm.dart'
    if (dart.library.js_interop) 'src/environment_specific/native_exports_js.dart';
export 'src/paint/video_animation_paintable.dart';
export 'src/paint/video_still_paintable.dart';
export 'src/playback/video_frame_scheduler.dart';
export 'src/renderer/video_frame_atlas.dart';
export 'src/renderer/video_frame_renderer.dart';
export 'src/renderer/video_frame_size.dart';
export 'src/renderer/video_frame_source.dart';
