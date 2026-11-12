/// The binding interface to the native Lottie renderer.
///
/// The value types (handle, info, features, load result, availability, render
/// status, engine version) compile everywhere. The bindings, the render job
/// and the frame codec use `dart:ffi` and are exported only where it exists.
library;

export 'src/lottie_availability.dart';
export 'src/lottie_features.dart';
export 'src/lottie_handle.dart';
export 'src/lottie_load_result.dart';
export 'src/lottie_native_version.dart';
export 'src/lottie_render_status.dart';
// The VM half is the default and the JS half the exception: the analyzer
// resolves a conditional export to its default URI, so the default must be
// the file that holds the bindings. `dart.library.js_interop` is true on every
// web compiler (dart2js and dart2wasm) and false on the VM.
export 'src/native_exports_vm.dart'
    if (dart.library.js_interop) 'src/native_exports_js.dart';
