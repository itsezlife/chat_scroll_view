/// Where the app keeps its caches, decided by which file the build picks.
///
/// The platform may clear these folders under storage pressure; only caches
/// go there.
library;

export 'cache_directory_vm.dart'
    if (dart.library.js_interop) 'cache_directory_js.dart';
