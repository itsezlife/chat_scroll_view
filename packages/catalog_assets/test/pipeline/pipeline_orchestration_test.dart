import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/testing.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter_test/flutter_test.dart';

import 'pipeline_harness.dart';

List<ContentDescriptor> stickers(int count, {bool thumbnails = false}) => [
  for (var n = 1; n <= count; n++) sticker(n, thumbnail: thumbnails),
];

/// The keys of [fetches] in the order they were made.
List<ContentKey> keysOf(Iterable<FakeFetch> fetches) => [
  for (final fetch in fetches) fetch.request.descriptor.key,
];

void main() {
  group('dedupe', () {
    test('surfaces on the same entry share one fetch and one decode', () async {
      final item = sticker(1);
      final harness = PipelineHarness(known: [item]);
      addTearDown(harness.dispose);

      final bindings = [
        harness.attach(item),
        harness.attach(item),
        harness.attach(item),
      ];
      await harness.settle();

      expect(harness.fetcher.fetches, hasLength(1));
      expect(harness.decoder.decodes, hasLength(1));
      expect(
        bindings.map((binding) => binding.readiness.stage),
        everyElement(AssetStage.full),
      );
    });

    test('the same content at two sizes is two entries', () async {
      final item = sticker(1);
      final harness = PipelineHarness(known: [item]);
      addTearDown(harness.dispose);

      harness
        ..attach(item)
        ..attach(item, const AssetSpec(pixelWidth: 128, pixelHeight: 128));
      await harness.settle();

      expect(harness.fetcher.fetches, hasLength(2));
    });

    test('an entry that is already full is not made again', () async {
      final item = sticker(1);
      final harness = PipelineHarness(known: [item]);
      addTearDown(harness.dispose);
      final first = harness.attach(item);
      await harness.settle();
      first.detach();

      final again = harness.attach(item);

      expect(again.readiness.stage, AssetStage.full);
      expect(harness.fetcher.fetches, hasLength(1));
    });
  });

  group('cancel when the last binding leaves', () {
    test('keeps working while another binding is attached', () async {
      final item = sticker(1);
      final harness = PipelineHarness(known: [item], autoFetch: false);
      addTearDown(harness.dispose);
      final first = harness.attach(item);
      harness.attach(item);

      first.detach();

      expect(harness.fetcher.fetches.single.isCancelled, isFalse);
    });

    test('cancels a running fetch and frees its slot', () async {
      final items = stickers(2);
      final harness = PipelineHarness(
        known: items,
        autoFetch: false,
        limits: const AssetPipelineLimits(maxConcurrentFetches: 1),
      );
      addTearDown(harness.dispose);
      final first = harness.attach(items[0]);
      harness.attach(items[1]);
      expect(harness.fetcher.fetches, hasLength(1));

      first.detach();

      expect(harness.fetcher.fetches[0].isCancelled, isTrue);
      expect(keysOf(harness.fetcher.fetches), [
        items[0].key,
        items[1].key,
      ], reason: 'the waiting entry took the slot');
    });

    test('drops queued work without ever fetching it', () async {
      final items = stickers(2);
      final harness = PipelineHarness(
        known: items,
        autoFetch: false,
        limits: const AssetPipelineLimits(maxConcurrentFetches: 1),
      );
      addTearDown(harness.dispose);
      harness.attach(items[0]);
      final queued = harness.attach(items[1]);

      queued.detach();
      harness.fetcher.fetches.single.complete();
      await harness.settle();

      expect(keysOf(harness.fetcher.fetches), [items[0].key]);
    });

    test('cancels a running decode and frees its slot', () async {
      final items = stickers(2);
      final harness = PipelineHarness(
        known: items,
        autoDecode: false,
        limits: const AssetPipelineLimits(maxConcurrentDecodes: 1),
      );
      addTearDown(harness.dispose);
      final first = harness.attach(items[0]);
      harness.attach(items[1]);
      await harness.settle();
      expect(harness.decoder.decodes, hasLength(1));

      first.detach();

      expect(harness.decoder.decodes[0].isCancelled, isTrue);
      expect(harness.decoder.decodes, hasLength(2));
    });

    test('ignores a fetch that finishes after the cancel', () async {
      final item = sticker(1);
      final harness = PipelineHarness(known: [item], autoFetch: false);
      addTearDown(harness.dispose);
      harness.attach(item).detach();

      harness.fetcher.fetches.single.complete();
      await harness.settle();

      expect(harness.decoder.decodes, isEmpty);
    });

    test('a later attach starts a fresh attempt', () async {
      final item = sticker(1);
      final harness = PipelineHarness(known: [item], autoFetch: false);
      addTearDown(harness.dispose);
      harness.attach(item).detach();

      final binding = harness.attach(item);
      harness.fetcher.fetches.last.complete();
      await harness.settle();

      expect(harness.fetcher.fetches, hasLength(2));
      expect(binding.readiness.stage, AssetStage.full);
    });
  });

  group('priority', () {
    late PipelineHarness harness;
    late List<ContentDescriptor> items;

    setUp(() {
      items = stickers(5, thumbnails: true);
      harness = PipelineHarness(
        known: items,
        autoFetch: false,
        limits: const AssetPipelineLimits(maxConcurrentFetches: 1),
      );
      addTearDown(harness.dispose);
    });

    /// Completes fetches one at a time, returning the order they ran in.
    Future<List<(ContentKey, FetchPart)>> drain() async {
      final order = <(ContentKey, FetchPart)>[];
      var seen = 0;
      while (harness.fetcher.fetches.length > seen) {
        final fetch = harness.fetcher.fetches[seen++];
        order.add((fetch.request.descriptor.key, fetch.request.part));
        fetch.complete();
        await harness.settle();
      }
      return order;
    }

    test('a thumbnail goes before content, content before preload', () async {
      // Holds the only slot, so the rest queue up.
      harness.attach(items[0]);
      harness.attach(items[1]).visible = false;
      harness.attach(items[2]);

      final order = await drain();

      // Thumbnails are one class, content follows the demand of its entry.
      expect(order, [
        (items[0].key, FetchPart.thumbnail),
        (items[1].key, FetchPart.thumbnail),
        (items[2].key, FetchPart.thumbnail),
        (items[0].key, FetchPart.content),
        (items[2].key, FetchPart.content),
        (items[1].key, FetchPart.content),
      ]);
    });

    test('is first come first served within a class', () async {
      harness.attach(items[0]);
      harness.attach(items[1]);
      harness.attach(items[2]);

      final order = await drain();

      expect(
        [
          for (final (key, part) in order)
            if (part == FetchPart.content) key,
        ],
        [items[0].key, items[1].key, items[2].key],
      );
    });

    test('follows an entry that is shown while it waits', () async {
      final noThumbnails = stickers(4);
      harness = PipelineHarness(
        known: noThumbnails,
        autoFetch: false,
        limits: const AssetPipelineLimits(maxConcurrentFetches: 1),
      );
      addTearDown(harness.dispose);
      harness.attach(noThumbnails[0]);
      harness.attach(noThumbnails[1]).visible = false;
      final promoted = harness.attach(noThumbnails[2])..visible = false;

      promoted.visible = true;
      final order = await drain();

      expect(
        [for (final (key, _) in order) key],
        [noThumbnails[0].key, noThumbnails[2].key, noThumbnails[1].key],
      );
    });

    test('hands the fetcher the class of each fetch', () async {
      harness.attach(items[0]).visible = false;
      await drain();

      expect(
        harness.fetcher.fetches[0].request.priority,
        AssetPriority.placeholder,
      );
      expect(
        harness.fetcher.fetches[1].request.priority,
        AssetPriority.preload,
      );
    });

    test('decodes are ordered the same way', () async {
      final noThumbnails = stickers(3);
      final decodes = PipelineHarness(
        known: noThumbnails,
        autoDecode: false,
        limits: const AssetPipelineLimits(maxConcurrentDecodes: 1),
      );
      addTearDown(decodes.dispose);
      decodes.attach(noThumbnails[0]);
      decodes.attach(noThumbnails[1]).visible = false;
      decodes.attach(noThumbnails[2]);
      await decodes.settle();

      for (var done = 0; done < 3; done++) {
        decodes.decoder.pending.single.complete();
        await decodes.settle();
      }

      expect(
        [
          for (final decode in decodes.decoder.decodes)
            decode.request.descriptor.key,
        ],
        [noThumbnails[0].key, noThumbnails[2].key, noThumbnails[1].key],
      );
    });
  });

  group('concurrency caps', () {
    test('never run more fetches than the cap', () async {
      final items = stickers(8);
      final harness = PipelineHarness(
        known: items,
        limits: const AssetPipelineLimits(maxConcurrentFetches: 3),
      );
      addTearDown(harness.dispose);

      items.forEach(harness.attach);
      await harness.settle();

      expect(harness.fetcher.peakConcurrency, 3);
      expect(harness.fetcher.fetches, hasLength(8));
    });

    test('never run more decodes than the cap', () async {
      final items = stickers(6);
      final harness = PipelineHarness(
        known: items,
        autoDecode: false,
        limits: const AssetPipelineLimits(maxConcurrentDecodes: 2),
      );
      addTearDown(harness.dispose);
      final bindings = items.map(harness.attach).toList();
      await harness.settle();

      while (harness.decoder.pending.isNotEmpty) {
        expect(harness.decoder.active, lessThanOrEqualTo(2));
        harness.decoder.pending.first.complete();
        await harness.settle();
      }

      expect(harness.decoder.peakConcurrency, 2);
      expect(
        bindings.map((binding) => binding.readiness.stage),
        everyElement(AssetStage.full),
      );
    });

    test('hold back fetching while too much fetched content waits', () async {
      final items = stickers(6);
      final harness = PipelineHarness(
        known: items,
        autoDecode: false,
        limits: const AssetPipelineLimits(
          maxConcurrentFetches: 1,
          maxConcurrentDecodes: 1,
          maxFetchedAwaitingDecode: 2,
        ),
      );
      addTearDown(harness.dispose);
      items.forEach(harness.attach);
      await harness.settle();

      // One decoding, two waiting: the fourth fetch is not started.
      expect(harness.decoder.decodes, hasLength(1));
      expect(harness.fetcher.fetches, hasLength(3));

      harness.decoder.pending.single.complete();
      await harness.settle();

      expect(harness.fetcher.fetches, hasLength(4));
    });

    test('a saturated pipeline does not delay a glyph binding', () async {
      final items = stickers(4);
      final harness = PipelineHarness(
        known: items,
        autoFetch: false,
        limits: const AssetPipelineLimits(maxConcurrentFetches: 1),
      );
      addTearDown(harness.dispose);
      final atlas = FakeGlyphSpriteSource(const ['😀', '😃']);
      addTearDown(atlas.dispose);
      harness.scope.glyphSource = atlas;
      items.forEach(harness.attach);
      final fetchesBefore = harness.fetcher.fetches.length;

      final glyph = harness.scope.attach(
        const ContentKey.unicode('😀'),
        spec,
        profile,
      );
      atlas.bakePage(0);

      expect(
        glyph.readiness,
        const AssetReadiness(AssetStage.full, isFinal: true),
      );
      expect(harness.fetcher.fetches, hasLength(fetchesBefore));
      glyph.detach();
    });
  });
}
