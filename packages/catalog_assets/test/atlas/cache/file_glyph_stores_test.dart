import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:catalog_assets/src/atlas/cache/file_glyph_cache_store.dart';
import 'package:catalog_assets/src/atlas/cache/file_glyph_page_store.dart';
import 'package:catalog_assets/src/atlas/cache/glyph_cache_key.dart';
import 'package:catalog_assets/testing.dart';
import 'package:flutter_test/flutter_test.dart';

Directory _tempDir() {
  final dir = Directory.systemTemp.createTempSync('glyph_cache_test_');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  return dir;
}

void main() {
  runGlyphPageStoreContract(
    'FileGlyphPageStore',
    () => FileGlyphPageStore(Directory('${_tempDir().path}/pages')),
  );

  late Directory cacheRoot;
  runGlyphCacheStoreContract(
    'FileGlyphCacheStore',
    () =>
        FileGlyphCacheStore(cacheRoot = Directory('${_tempDir().path}/cache')),
    reopen: (_) => FileGlyphCacheStore(cacheRoot),
  );

  group('FileGlyphPageStore damage', () {
    late Directory dir;
    late FileGlyphPageStore store;

    Image page() {
      final recorder = PictureRecorder();
      Canvas(recorder).drawRect(
        const Rect.fromLTWH(0, 0, 4, 4),
        Paint()
          ..color = const Color(0x80FF0000)
          ..isAntiAlias = false,
      );
      final picture = recorder.endRecording();
      final image = picture.toImageSync(16, 16);
      picture.dispose();
      return image;
    }

    File fileOf(int index) => File('${dir.path}/page_$index.glyphpage');

    setUp(() async {
      dir = Directory('${_tempDir().path}/pages');
      store = FileGlyphPageStore(dir);
      final image = page();
      await store.write(0, image);
      image.dispose();
    });

    test('a semi-transparent pixel survives the round trip', () async {
      final read = (await store.read(0))!;
      final pixels = (await ImagePixels.of(read)).at(1, 1);
      read.dispose();
      final original = page();
      final expected = (await ImagePixels.of(original)).at(1, 1);
      original.dispose();
      expect(pixels, expected);
      expect(pixels.a, lessThan(1));
    });

    test('a truncated page file is a miss', () async {
      final bytes = fileOf(0).readAsBytesSync();
      fileOf(
        0,
      ).writeAsBytesSync(Uint8List.sublistView(bytes, 0, bytes.length - 7));
      expect(await store.read(0), isNull);
    });

    test('a file shorter than its header is a miss', () async {
      fileOf(0).writeAsBytesSync(Uint8List(5));
      expect(await store.read(0), isNull);
    });

    test('a file with the wrong magic is a miss', () async {
      final bytes = fileOf(0).readAsBytesSync();
      bytes[0] = 0;
      fileOf(0).writeAsBytesSync(bytes);
      expect(await store.read(0), isNull);
    });

    test('a leftover temporary file is not a page', () async {
      File('${dir.path}/page_3.glyphpage.tmp').writeAsBytesSync(Uint8List(40));
      expect(await store.read(3), isNull);
    });
  });

  group('FileGlyphCacheStore damage', () {
    const key = GlyphCacheKey(
      artVersion: 'a',
      devicePixelRatio: 2,
      glyphSize: 72,
      layoutVersion: 1,
      catalogueHash: 'h',
    );
    const record = GlyphCacheRecord(key: key, glyphs: ['x']);
    late Directory root;
    late FileGlyphCacheStore store;

    setUp(() async {
      root = Directory('${_tempDir().path}/cache');
      store = FileGlyphCacheStore(root);
      await store.stage(record);
      await store.commit();
    });

    test('a damaged manifest means nothing is committed', () async {
      File('${root.path}/manifest.json').writeAsStringSync('gen_0\n{broken');
      expect(await FileGlyphCacheStore(root).openCommitted(), isNull);
    });

    test(
      'a manifest naming a nonsense directory means nothing is committed',
      () async {
        File('${root.path}/manifest.json').writeAsStringSync('../etc\n{}');
        expect(await FileGlyphCacheStore(root).openCommitted(), isNull);
      },
    );

    test('a missing manifest means nothing is committed', () async {
      File('${root.path}/manifest.json').deleteSync();
      expect(await FileGlyphCacheStore(root).openCommitted(), isNull);
    });

    test('staging sweeps generations the manifest does not name', () async {
      Directory('${root.path}/gen_7').createSync();
      await FileGlyphCacheStore(root).stage(record);
      expect(Directory('${root.path}/gen_7').existsSync(), isFalse);
      expect(Directory('${root.path}/gen_0').existsSync(), isTrue);
    });

    test('committing removes the previous generation directory', () async {
      final next = FileGlyphCacheStore(root);
      await next.stage(record);
      await next.commit();
      expect(Directory('${root.path}/gen_0').existsSync(), isFalse);
      expect(Directory('${root.path}/gen_1').existsSync(), isTrue);
    });
  });
}
