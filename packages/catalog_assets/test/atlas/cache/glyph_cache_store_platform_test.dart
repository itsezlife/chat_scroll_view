import 'dart:io';

import 'package:catalog_assets/glyph_atlas.dart';
import 'package:catalog_assets/src/atlas/environment_specific/glyph_cache_store_file_vm.dart';
import 'package:catalog_assets/src/atlas/environment_specific/glyph_cache_store_js.dart'
    as js;
import 'package:catalog_assets/src/atlas/environment_specific/glyph_cache_store_vm.dart'
    as vm;
import 'package:flutter_test/flutter_test.dart';

/// The platform fork is two files; a VM test can build only the default one,
/// so both are exercised directly.
void main() {
  test('a platform with a file system persists under the given directory', () {
    final dir = Directory.systemTemp.createTempSync('glyph_platform_');
    addTearDown(() => dir.deleteSync(recursive: true));

    final store = vm.$createGlyphCacheStore(dir.path);

    expect(store, isA<GlyphCacheStore$File$VM>());
    expect((store as GlyphCacheStore$File$VM).root.path, dir.path);
    // The default build of this test is the VM one.
    expect(
      GlyphCacheStore.forPlatform(dir.path),
      isA<GlyphCacheStore$File$VM>(),
    );
  });

  test('the web keeps pages in memory and touches no directory', () async {
    final store = js.$createGlyphCacheStore('/never/used');

    expect(store, isA<MemoryGlyphCacheStore>());
    expect(await store.openCommitted(), isNull);
  });
}
