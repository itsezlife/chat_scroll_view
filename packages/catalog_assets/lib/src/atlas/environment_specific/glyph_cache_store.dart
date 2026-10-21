/// Where a platform keeps persisted glyph pages, decided by which file the
/// build picks: the hub behind [GlyphCacheStore.forPlatform].
library;

export 'glyph_cache_store_vm.dart'
    if (dart.library.js_interop) 'glyph_cache_store_js.dart';
