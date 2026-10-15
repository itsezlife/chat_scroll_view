import 'package:catalog_assets/src/atlas/cache/glyph_cache_store.dart';
import 'package:catalog_assets/src/atlas/cache/memory_glyph_cache_store.dart';

/// The web has no disk cache: the store lives and dies with the page.
///
/// Takes the arguments of the io counterpart and ignores [directoryPath], so
/// the two files are interchangeable at the call site.
GlyphCacheStore createGlyphCacheStoreForPlatform(String directoryPath) =>
    MemoryGlyphCacheStore();
