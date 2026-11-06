// The io file is the default and the stub the exception: the analyzer
// resolves a conditional export to its default URI, so the file holding the
// real implementation must be the default. `dart.library.js_interop` is true
// on every web compiler and false on the VM.
export 'package:lottie_decoder/src/cache/frame_cache_files_io.dart'
    if (dart.library.js_interop) 'package:lottie_decoder/src/cache/frame_cache_files_stub.dart'
    show openFrameCacheFiles;
