/// How the media store's folder is swept, decided by which file the build
/// picks: the hub behind `MediaDiskCache.sweep`.
library;

export 'media_disk_sweep_vm.dart'
    if (dart.library.js_interop) 'media_disk_sweep_js.dart';
