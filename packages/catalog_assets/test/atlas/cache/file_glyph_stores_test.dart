import 'dart:io';
import 'dart:ui';

import 'package:catalog_assets/src/atlas/cache/file_glyph_cache_store.dart';
import 'package:catalog_assets/src/atlas/cache/file_glyph_page_store.dart';
import 'package:catalog_assets/src/atlas/cache/glyph_cache_key.dart';
import 'package:catalog_assets/testing.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

Directory _tempDir() {
  final dir = Directory.systemTemp.createTempSync('glyph_cache_test_');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  return dir;
}

/// Collects what is reported through [FlutterError.onError] until the end of
/// the test.
List<FlutterErrorDetails> _captureErrors() {
  final reported = <FlutterErrorDetails>[];
  final previous = FlutterError.onError;
  FlutterError.onError = reported.add;
  addTearDown(() => FlutterError.onError = previous);
  return reported;
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

    test('a page that is simply absent is a quiet miss', () async {
      final reported = _captureErrors();
      expect(await store.read(9), isNull);
      expect(reported, isEmpty);
    });

    test('a page that cannot be read for another reason is reported, with '
        'its stack, and is still a miss', () async {
      final reported = _captureErrors();
      // A directory where the file should be: present, but not readable.
      Directory('${dir.path}/page_5.glyphpage').createSync();

      expect(await store.read(5), isNull);

      expect(reported, hasLength(1));
      expect(reported.single.stack, isNotNull);
      expect(reported.single.library, 'catalog_assets');
    });

    test('a page the engine cannot decode is reported and is a miss', () async {
      final reported = _captureErrors();
      final failing = FileGlyphPageStore(
        dir,
        decode: (pixels, width, height, format, onDecoded) =>
            throw StateError('no decoder'),
      );

      expect(await failing.read(0), isNull);

      expect(reported, hasLength(1));
      expect(reported.single.exception, isA<StateError>());
      expect(reported.single.stack, isNotNull);
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

    test('a missing manifest means nothing is committed, quietly', () async {
      final reported = _captureErrors();
      File('${root.path}/manifest.json').deleteSync();
      expect(await FileGlyphCacheStore(root).openCommitted(), isNull);
      expect(reported, isEmpty);
    });

    test('a manifest that cannot be read is reported, not hidden', () async {
      final reported = _captureErrors();
      File('${root.path}/manifest.json').deleteSync();
      Directory('${root.path}/manifest.json').createSync();

      expect(await FileGlyphCacheStore(root).openCommitted(), isNull);

      expect(reported, hasLength(1));
      expect(reported.single.stack, isNotNull);
      expect(reported.single.library, 'catalog_assets');
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
