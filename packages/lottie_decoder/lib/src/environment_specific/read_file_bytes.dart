/// How a decoder reads a `FetchedFile`, decided by which file the build picks.
library;

export 'read_file_bytes_vm.dart'
    if (dart.library.js_interop) 'read_file_bytes_js.dart';
