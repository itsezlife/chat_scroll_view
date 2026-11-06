// The io file is the default and the stub the exception: the analyzer
// resolves a conditional export to its default URI, so the file that holds
// the real implementation must be the default. `dart.library.js_interop` is
// true on every web compiler and false on the VM.
export 'package:video_decoder/src/decoder/read_file_bytes_io.dart'
    if (dart.library.js_interop) 'package:video_decoder/src/decoder/read_file_bytes_stub.dart';
