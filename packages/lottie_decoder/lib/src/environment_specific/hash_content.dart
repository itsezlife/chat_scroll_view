/// Where a decoder hashes a file by default, decided by which file the build
/// picks.
library;

export 'hash_content_vm.dart'
    if (dart.library.js_interop) 'hash_content_js.dart';
