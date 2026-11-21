/// The camera's captures as media: the asset cache's fetcher and the
/// viewer's players find them by their local key in the capture cache.
library;

import 'dart:typed_data';

import 'package:chat_scroll_view_example/src/common/capture_media.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_bytes_cache/http_bytes_cache.dart';
import 'package:mpx_capture/mpx_capture.dart';
import 'package:mpx_core/mpx_core.dart';

final _key = MediaKey$Local('00000000-0000-4000-8000-000000000001');

final class _Elsewhere implements ContentFetcher {
  final List<MediaKey> asked = [];

  @override
  Future<FetchedContent> fetch(FetchRequest request) async {
    asked.add(request.descriptor.key);
    throw StateError('not here');
  }

  @override
  bool needsDownload(MediaKey key) => true;
}

void main() {
  test("a capture's thumbnail and its picture come from the capture cache's "
      'store; other keys go on', () async {
    final store = MemoryBytesCache();
    final client = HttpBytesClient();
    addTearDown(() async {
      await client.close();
      await store.close();
    });
    await store.write(
      CaptureCache.cacheKeyOf(_key),
      Uint8List.fromList([1, 2, 3]),
    );
    final elsewhere = _Elsewhere();
    final fetcher = CaptureMedia.fetcher(
      store: store,
      client: client,
      otherwise: elsewhere,
    );
    final fetched = await fetcher.fetch(
      FetchRequest(
        descriptor: MediaDescriptor(key: _key, kind: MediaKind.still),
        part: FetchPart.content,
        priority: AssetPriority.visible,
        cancellation: CancellationToken(),
      ),
    );
    expect(fetched, isA<FetchedBytes>());
    expect((fetched as FetchedBytes).bytes, [1, 2, 3]);
    expect(fetcher.needsDownload(_key), isFalse);

    const other = MediaKey.remote('x');
    await expectLater(
      fetcher.fetch(
        FetchRequest(
          descriptor: const MediaDescriptor(key: other, kind: MediaKind.still),
          part: FetchPart.content,
          priority: AssetPriority.visible,
          cancellation: CancellationToken(),
        ),
      ),
      throwsStateError,
    );
    expect(elsewhere.asked, [other]);
  });

  test("a captured video plays from the capture cache's ranged resource", () {
    final sources = CaptureMedia.playerSourcesOf(_key);
    expect(sources, hasLength(1));
    expect(sources.single.request.cacheKey, CaptureCache.cacheKeyOf(_key));
    expect(sources.single.mimeType, 'video/mp4');
    expect(CaptureMedia.playerSourcesOf(const MediaKey.remote('x')), isEmpty);
  });
}
