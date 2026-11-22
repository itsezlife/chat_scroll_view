import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:typed_data';

import 'package:chat_scroll_view_example/src/features/chat/wallpaper/downloaded_pattern.dart';
import 'package:flutter/painting.dart' show Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:http_bytes_cache/http_bytes_cache.dart';
import 'package:mpx_svg/mpx_svg.dart';
import 'package:vector_graphics/vector_graphics.dart';

final Uint8List _pattern = Uint8List.fromList(
  gzip.encode(
    utf8.encode(
      '<svg xmlns="http://www.w3.org/2000/svg" width="40" height="80"> '
      '<path d="M0 0h10v10H0z"/></svg>',
    ),
  ),
);

void main() {
  late MemoryBytesCache store;
  late int downloads;

  setUp(() {
    store = MemoryBytesCache();
    downloads = 0;
  });

  DownloadedPattern pattern(Uint8List tgv) => DownloadedPattern(
    slug: 'doodles',
    download: () async {
      downloads++;
      return tgv;
    },
    compiled: store,
  );

  test('a downloaded gzipped pattern is drawn as vector artwork', () async {
    final info = await vg.loadPicture(pattern(_pattern), null);

    expect(info.size, const Size(40, 80));
    info.picture.dispose();
  });

  test('its compiled form is kept, so the next start does not download or '
      'parse it again', () async {
    final first = await pattern(_pattern).loadBytes(null);

    final again = await pattern(_pattern).loadBytes(null);

    expect(downloads, 1);
    expect(again.lengthInBytes, first.lengthInBytes);
  });

  test(
    'a pattern the limits refuse fails, so the wallpaper keeps its fill',
    () async {
      final hostile = Uint8List.fromList(
        gzip.encode(
          utf8.encode(
            '<svg xmlns="http://www.w3.org/2000/svg"><script/></svg>',
          ),
        ),
      );

      await expectLater(
        pattern(hostile).loadBytes(null),
        throwsA(isA<SvgRejection>()),
      );
    },
  );

  test('loaders of one slug are one cache key', () {
    expect(pattern(_pattern).cacheKey(null), pattern(_pattern).cacheKey(null));
  });
}
