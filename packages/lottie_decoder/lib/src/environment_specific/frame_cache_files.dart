/// Where a frame cache keeps its entries, decided by which file the build
/// picks: the hub behind `FrameCache(directoryPath:)`.
library;

export 'frame_cache_files_vm.dart'
    if (dart.library.js_interop) 'frame_cache_files_js.dart';
