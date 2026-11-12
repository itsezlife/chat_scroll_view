/// How the local sticker corpus is read, decided by which file the build
/// picks: the hub behind `CorpusStickerPack`.
library;

export 'corpus_files_vm.dart'
    if (dart.library.js_interop) 'corpus_files_js.dart';
