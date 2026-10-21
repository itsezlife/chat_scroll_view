import 'package:catalog_assets/src/atlas/cache/glyph_cache_store.dart';
import 'package:catalog_assets/src/atlas/cache/memory_glyph_cache_store.dart';

/// The web hook behind [GlyphCacheStore.forPlatform]: the web has no disk
/// cache worth using for 16 MiB pages and bakes nothing anyway, so the store
/// lives and dies with the page. [directoryPath] is ignored.
GlyphCacheStore $createGlyphCacheStore(String directoryPath) =>
    MemoryGlyphCacheStore();
