/// Whether there is a disk tier for bytes, decided by which file the build
/// picks: the hub behind `ByteCache.directory`.
library;

export 'byte_cache_vm.dart' if (dart.library.js_interop) 'byte_cache_js.dart';
