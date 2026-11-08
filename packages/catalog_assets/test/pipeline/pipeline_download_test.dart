import 'package:catalog_assets/catalog_assets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'pipeline_harness.dart';

void main() {
  group('the fetcher reports the download of the content', () {
    test('received bytes over the total reach the binding', () async {
      final item = sticker(1);
      final harness = PipelineHarness(known: [item], autoFetch: false);
      addTearDown(harness.dispose);
      final binding = harness.attach(item);
      final fetch = harness.fetcher.fetchesOf(item.key).single;

      fetch.receive(0, 400);
      expect(binding.downloadProgress, 0);

      fetch.receive(100, 400);
      expect(binding.downloadProgress, 0.25);
    });

    test('an unknown total is a download at zero', () async {
      final item = sticker(1);
      final harness = PipelineHarness(known: [item], autoFetch: false);
      addTearDown(harness.dispose);
      final binding = harness.attach(item);

      harness.fetcher.fetchesOf(item.key).single.receive(5000, null);

      expect(binding.downloadProgress, 0);
    });

    test('a finished transfer is all of it until the content is decoded', () {
      final item = sticker(1);
      final harness = PipelineHarness(
        known: [item],
        autoFetch: false,
        autoDecode: false,
      );
      addTearDown(harness.dispose);
      final binding = harness.attach(item);

      return Future(() async {
        harness.fetcher.fetchesOf(item.key).single
          ..receive(10, 400)
          ..complete();
        await harness.settle();

        expect(binding.downloadProgress, 1);

        harness.decoder.decodes.single.complete();
        await harness.settle();

        expect(binding.readiness.stage, AssetStage.full);
        expect(binding.downloadProgress, isNull);
      });
    });

    test('a fetch that reports nothing (a cache hit) shows no download', () {
      final item = sticker(1);
      final harness = PipelineHarness(
        known: [item],
        autoFetch: false,
        autoDecode: false,
      );
      addTearDown(harness.dispose);
      final binding = harness.attach(item);

      return Future(() async {
        harness.fetcher.fetchesOf(item.key).single.complete();
        await harness.settle();

        expect(binding.downloadProgress, isNull);
      });
    });

    test('the thumbnail download is not the content download', () {
      final item = sticker(1, thumbnail: true);
      final harness = PipelineHarness(known: [item], autoFetch: false);
      addTearDown(harness.dispose);
      final binding = harness.attach(item);

      harness.fetcher
          .fetchesOf(item.key, FetchPart.thumbnail)
          .single
          .receive(10, 20);

      expect(binding.downloadProgress, isNull);
    });

    test('a report after the fetch was cancelled is ignored', () {
      final item = sticker(1);
      final harness = PipelineHarness(known: [item], autoFetch: false);
      addTearDown(harness.dispose);
      final binding = harness.attach(item);
      final fetch = harness.fetcher.fetchesOf(item.key).single;

      binding.detach();
      fetch.receive(10, 20);

      final again = harness.attach(item);
      expect(again.downloadProgress, isNull);
    });
  });
}
