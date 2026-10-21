import 'dart:io';

import 'package:catalog_assets/src/atlas/cache/glyph_cache_store.dart';
import 'package:catalog_assets/src/atlas/environment_specific/glyph_cache_store_file_vm.dart';

/// The VM hook behind [GlyphCacheStore.forPlatform]: pages in the directory at
/// [directoryPath], through `dart:io` and no plugin.
GlyphCacheStore $createGlyphCacheStore(String directoryPath) =>
    GlyphCacheStore$File$VM(Directory(directoryPath));
