/// The camera's captures as media: the asset cache's fetcher and the
/// viewer's players find them by their local key in the capture cache.
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:chat_outbox/testing.dart';
import 'package:chat_scroll_view_example/src/app/app_services.dart';
import 'package:chat_scroll_view_example/src/common/capture_media.dart';
import 'package:content_model/testing.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_bytes_cache/http_bytes_cache.dart';
import 'package:mpx/testing.dart';
import 'package:mpx_capture/mpx_capture.dart';
import 'package:mpx_core/mpx_core.dart';
import 'package:mpx_library/mpx_library.dart';
import 'package:mpx_ui/mpx_ui.dart';

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

  testWidgets("the picker viewer's full picture of a capture loads from the "
      "capture cache, through the app's own pipeline", (tester) async {
    final signals = FakeDeviceSignals();
    addTearDown(signals.dispose);
    final services = (await tester.runAsync(
      () => AppServices.create(
        // No transfer engine: it journals on disk, which a test has not.
        outboxTransfers: FakeOutboxTransfers(),
        keyValueStore: FakeKeyValueStore(),
        assetLoader: rootBundle.loadString,
        clipboard: FakeRichClipboard(),
        deviceSignals: signals,
      ),
    ))!;
    addTearDown(services.dispose);
    // A 64x48 PNG shot, put the way the capture surface puts one.
    final directory = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('capture-viewer'),
    ))!;
    addTearDown(() => directory.deleteSync(recursive: true));
    final key = services.captureCache.mintKey();
    await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawRect(
        const Rect.fromLTWH(0, 0, 64, 48),
        Paint()..color = const Color(0xFF3366CC),
      );
      final image = await recorder.endRecording().toImage(64, 48);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      final file = File('${directory.path}/shot.png');
      await file.writeAsBytes(png!.buffer.asUint8List());
      await services.captureCache.put(
        key,
        CaptureOutput(
          path: file.path,
          size: png.lengthInBytes,
          duration: Duration.zero,
          dimensions: const MediaDimensions(64, 48),
          headerRewritten: false,
        ),
      );
    });

    // What the picker viewer's page asks for: the capture's own descriptor
    // (no library thumbnail stands in), at the page's size.
    final capture = PickerCapture(
      key: key,
      kind: LibraryAssetKind.photo,
      dimensions: const MediaDimensions(64, 48),
    );
    final descriptor = PickerCaptureKeys.descriptorOf(
      capture.asset,
      thumbnailPixels: 100,
    );
    expect(descriptor.key, key);
    expect(descriptor.thumbnail, isNull);
    final scope = services.assets.media..know(descriptor);
    final preset = AssetPresets.media(
      size: const Size(400, 800),
      devicePixelRatio: 1,
      profile: const AssetProfile(animate: true),
    );
    final binding = scope.attach(key, preset.spec, preset.profile);
    addTearDown(binding.detach);
    for (var i = 0; i < 100 && scope.pictureSizeOf(key) == null; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(scope.pictureSizeOf(key), const Size(64, 48));
  });
}
