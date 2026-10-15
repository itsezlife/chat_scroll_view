import 'dart:io';

import 'package:catalog_assets/src/atlas/cache/file_glyph_cache_store.dart';
import 'package:catalog_assets/src/atlas/cache/glyph_cache_store.dart';

/// A [GlyphCacheStore] keeping its pages in the directory at [directoryPath].
///
/// The host picks the directory (an application support or cache directory
/// from its own path lookup; this package adds no plugin for it) and gives it
/// to this store alone. The platform may clear a cache directory at any time,
/// which only costs a re-bake.
GlyphCacheStore createGlyphCacheStoreForPlatform(String directoryPath) =>
    FileGlyphCacheStore(Directory(directoryPath));
