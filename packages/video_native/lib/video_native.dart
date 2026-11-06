/// The binding interface to the native video decoder.
///
/// The value types (handle, info, open result, frame result, availability)
/// compile everywhere. The bindings use `dart:ffi` and are exported only where
/// it exists.
library;

// The native file is the default and the stub the exception because the
// analyzer resolves a conditional export to its default URI and ignores
// `dart.library.ffi`. `dart.library.js_interop` is true on every web compiler
// and false on the VM.
export 'src/native_exports.dart'
    if (dart.library.js_interop) 'src/native_exports_stub.dart';
export 'src/video_availability.dart';
export 'src/video_frame_result.dart';
export 'src/video_handle.dart';
export 'src/video_open_result.dart';
