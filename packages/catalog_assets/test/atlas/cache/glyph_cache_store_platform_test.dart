import 'dart:io';

import 'package:catalog_assets/glyph_atlas.dart';
import 'package:catalog_assets/src/atlas/cache/file_glyph_cache_store.dart';
import 'package:catalog_assets/src/atlas/platform/glyph_cache_store_platform_io.dart'
    as io;
import 'package:catalog_assets/src/atlas/platform/glyph_cache_store_platform_web.dart'
    as web;
import 'package:flutter_test/flutter_test.dart';

/// The platform fork is two files; a VM test can build only the default one,
/// so both are exercised directly.
void main() {
  test('a platform with a file system persists under the given directory', () {
    final dir = Directory.systemTemp.createTempSync('glyph_platform_');
    addTearDown(() => dir.deleteSync(recursive: true));

    final store = io.createGlyphCacheStoreForPlatform(dir.path);

    expect(store, isA<FileGlyphCacheStore>());
    expect((store as FileGlyphCacheStore).root.path, dir.path);
    // The default build of this test is the io one.
    expect(
      createGlyphCacheStoreForPlatform(dir.path),
      isA<FileGlyphCacheStore>(),
    );
  });

  test('the web keeps pages in memory and touches no directory', () async {
    final store = web.createGlyphCacheStoreForPlatform('/never/used');

    expect(store, isA<MemoryGlyphCacheStore>());
    expect(await store.openCommitted(), isNull);
  });
}
