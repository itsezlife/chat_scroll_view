// The native file is the default and the stub the exception because the
// analyzer resolves a conditional export to its default URI and ignores
// `dart.library.ffi`. `dart.library.js_interop` is true on every web compiler
// and false on the VM.
export 'platform_host_ffi.dart'
    if (dart.library.js_interop) 'platform_host_stub.dart';
