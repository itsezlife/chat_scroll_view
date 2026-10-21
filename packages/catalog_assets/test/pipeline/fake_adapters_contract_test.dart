import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/testing.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter_test/flutter_test.dart';

import 'pipeline_harness.dart';

FetchRequest _request(ContentDescriptor descriptor) => FetchRequest(
  descriptor: descriptor,
  part: FetchPart.content,
  priority: AssetPriority.visible,
  cancellation: CancellationToken(),
);

void main() {
  final available = sticker(1, thumbnail: true);
  final missing = sticker(2, thumbnail: true);

  AssetFetcherContract.run(() {
    final clock = ManualClock();
    final fetcher = FakeFetcher(
      contents: {available.key: bytes},
      thumbnails: {available.thumbnail!: bytes},
      latency: const Duration(milliseconds: 100),
      clock: clock,
    );
    return AssetFetcherHarness(
      fetcher: fetcher,
      available: available,
      missing: missing,
      elapse: () => clock.advance(const Duration(milliseconds: 100)),
      goOffline: () => fetcher.online = false,
      goOnline: () => fetcher.online = true,
    );
  });

  DecoderContract.run(
    () => DecoderHarness(
      decoder: FakeDecoder(reportFirstFrame: true),
      valid: (part, spec) => DecodeRequest(
        descriptor: available,
        spec: spec,
        part: part,
        content: bytes,
      ),
      invalid: () => DecodeRequest(
        descriptor: available,
        spec: const AssetSpec(pixelWidth: 64, pixelHeight: 64),
        part: FetchPart.content,
        content: FetchedContent.bytes(FakeDecoder.corrupt),
      ),
    ),
  );

  group('FakeFetcher', () {
    test('answers after its latency on the manual clock', () async {
      final clock = ManualClock();
      final fetcher = FakeFetcher(
        contents: {available.key: bytes},
        latency: const Duration(seconds: 1),
        clock: clock,
      );
      var done = false;
      fetcher.fetch(_request(available)).then((_) => done = true).ignore();

      clock.advance(const Duration(milliseconds: 999));
      await Future<void>.delayed(Duration.zero);
      expect(done, isFalse);

      clock.advance(const Duration(milliseconds: 1));
      await Future<void>.delayed(Duration.zero);
      expect(done, isTrue);
    });

    test('hands a file through untouched', () async {
      final fetcher = FakeFetcher(
        contents: {available.key: const FetchedContent.file('/clip.webm')},
      );

      final content = await fetcher.fetch(_request(available));

      expect((content as FetchedFile).path, '/clip.webm');
    });

    test('counts the most fetches in flight at once', () {
      final fetcher = FakeFetcher(autoRespond: false);
      for (var n = 0; n < 3; n++) {
        fetcher.fetch(_request(available)).ignore();
      }
      fetcher.fetches.first.fail(const FetchFailure.transient('x'));

      expect(fetcher.peakConcurrency, 3);
      expect(fetcher.active, 2);
    });
  });
}
