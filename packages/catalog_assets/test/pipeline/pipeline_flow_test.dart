import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/testing.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter_test/flutter_test.dart';

import 'pipeline_harness.dart';

void main() {
  _misbehaving();

  group('fetching and decoding', () {
    test('an entry goes from none to full through fetch and decode', () async {
      final item = sticker(1);
      final harness = PipelineHarness(known: [item]);
      addTearDown(harness.dispose);

      final binding = harness.attach(item);
      expect(binding.readiness.stage, AssetStage.none);
      await harness.settle();

      expect(
        binding.readiness,
        const AssetReadiness(AssetStage.full, isFinal: true),
      );
      expect(harness.fetcher.fetches.single.request.part, FetchPart.content);
      expect(harness.decoder.decodes.single.request.spec, spec);
    });

    test(
      'a thumbnail is the placeholder stage while the content loads',
      () async {
        final item = sticker(1, thumbnail: true);
        final harness = PipelineHarness(known: [item], autoFetch: false);
        addTearDown(harness.dispose);
        final binding = harness.attach(item);

        harness.fetcher
            .fetchesOf(item.key, FetchPart.thumbnail)
            .single
            .complete();
        await harness.settle();

        expect(binding.readiness.stage, AssetStage.placeholder);
        expect(binding.readiness.isFinal, isFalse);

        harness.fetcher
            .fetchesOf(item.key, FetchPart.content)
            .single
            .complete();
        await harness.settle();

        expect(binding.readiness.stage, AssetStage.full);
      },
    );

    test('a thumbnail that arrives after the content is dropped', () async {
      final item = sticker(1, thumbnail: true);
      final harness = PipelineHarness(known: [item], autoFetch: false);
      addTearDown(harness.dispose);
      final binding = harness.attach(item);

      harness.fetcher.fetchesOf(item.key, FetchPart.content).single.complete();
      await harness.settle();

      expect(binding.readiness.stage, AssetStage.full);
      final thumbnail = harness.fetcher
          .fetchesOf(item.key, FetchPart.thumbnail)
          .single;
      expect(
        thumbnail.isCancelled,
        isTrue,
        reason: 'a finished entry needs no stand-in',
      );
    });

    test('a decoder that reports the first frame early shows it', () async {
      final item = sticker(1);
      final harness = PipelineHarness(
        known: [item],
        autoDecode: false,
        firstFrameEarly: true,
      );
      addTearDown(harness.dispose);
      final binding = harness.attach(item);
      await harness.settle();

      harness.decoder.decodes.single.advance(AssetStage.firstFrame);
      expect(binding.readiness.stage, AssetStage.firstFrame);

      harness.decoder.decodes.single.complete();
      expect(binding.readiness.stage, AssetStage.full);
    });

    test('a first-frame-only spec is final at the first frame', () async {
      final item = sticker(1);
      final harness = PipelineHarness(known: [item]);
      addTearDown(harness.dispose);

      final binding = harness.attach(item, firstFrameSpec);
      await harness.settle();

      expect(
        binding.readiness,
        const AssetReadiness(AssetStage.firstFrame, isFinal: true),
      );
    });

    test('a failed thumbnail does not fail the entry', () async {
      final item = sticker(1, thumbnail: true);
      final harness = PipelineHarness(known: [item], autoFetch: false);
      addTearDown(harness.dispose);
      final binding = harness.attach(item);

      harness.fetcher
          .fetchesOf(item.key, FetchPart.thumbnail)
          .single
          .fail(const FetchFailure.permanent('no thumbnail'));
      await harness.settle();
      harness.fetcher.fetchesOf(item.key, FetchPart.content).single.complete();
      await harness.settle();

      expect(binding.readiness.stage, AssetStage.full);
      expect(binding.lastError, isNull);
    });

    test('data the decoder rejects leaves the entry where it was', () async {
      final item = sticker(1);
      final harness = PipelineHarness(known: [item]);
      addTearDown(harness.dispose);
      harness.fetcher.serve(
        item.key,
        FetchedContent.bytes(FakeDecoder.corrupt),
      );

      final binding = harness.attach(item);
      await harness.settle();

      expect(binding.readiness.stage, AssetStage.none);
      expect(binding.lastError, isA<FormatException>());
    });

    test('a media form without a decoder is not fetched', () async {
      const video = ContentDescriptor(
        key: ContentKey.document('clip-1'),
        mediaForm: MediaForm.video,
      );
      final harness = PipelineHarness(known: [video]);
      addTearDown(harness.dispose);

      final binding = harness.attach(video);
      await harness.settle();

      expect(harness.fetcher.fetches, isEmpty);
      expect(binding.lastError, isA<AssetPipelineError>());
      expect(binding.readiness.stage, AssetStage.none);
    });
  });
}

void _misbehaving() {
  group('misbehaving adapters', () {
    test('a decoder failure is permanent whatever the decoder says', () async {
      final item = sticker(1);
      final harness = PipelineHarness(known: [item]);
      addTearDown(harness.dispose);
      harness.fetcher.serve(
        item.key,
        FetchedContent.bytes(FakeDecoder.corrupt),
      );
      final binding = harness.attach(item);
      await harness.settle();
      final before = harness.fetcher.fetches.length;

      harness.scope.connectivityRestored();
      await harness.settle();

      expect(binding.lastError, isNotNull);
      expect(harness.fetcher.fetches, hasLength(before));
    });

    test(
      'a fetcher that throws instead of failing is a transient failure',
      () async {
        final item = sticker(1);
        final scope = AssetCacheScope(
          producer: AssetPipeline(
            fetcher: _ThrowingFetcher(),
            decoders: DecoderRegistry()
              ..register(MediaForm.still, FakeDecoder()),
          )..know(item),
          clock: PlaybackClock(ticks: ManualPlaybackTickSource()),
        );
        addTearDown(scope.dispose);

        final binding = scope.attach(item.key, spec, profile);
        await Future<void>.delayed(Duration.zero);

        expect(binding.lastError, isStateError);
        expect(binding.readiness.stage, AssetStage.none);
      },
    );

    test(
      'a decoder that throws instead of failing is a failed attempt',
      () async {
        final item = sticker(1);
        final scope = AssetCacheScope(
          producer: AssetPipeline(
            fetcher: FakeFetcher(contents: {item.key: bytes}),
            decoders: DecoderRegistry()
              ..register(MediaForm.still, _ThrowingDecoder()),
          )..know(item),
          clock: PlaybackClock(ticks: ManualPlaybackTickSource()),
        );
        addTearDown(scope.dispose);

        final binding = scope.attach(item.key, spec, profile);
        await Future<void>.delayed(Duration.zero);

        expect(binding.lastError, isStateError);
      },
    );

    test(
      'a decoder that cancels itself ends the attempt without an error',
      () async {
        final item = sticker(1);
        final scope = AssetCacheScope(
          producer: AssetPipeline(
            fetcher: FakeFetcher(contents: {item.key: bytes}),
            decoders: DecoderRegistry()
              ..register(MediaForm.still, _GivingUpDecoder()),
          )..know(item),
          clock: PlaybackClock(ticks: ManualPlaybackTickSource()),
        );
        addTearDown(scope.dispose);

        final binding = scope.attach(item.key, spec, profile);
        await Future<void>.delayed(Duration.zero);

        expect(binding.lastError, isNull);
        expect(binding.readiness.stage, AssetStage.none);
      },
    );
  });

  group('the pipeline', () {
    test('hands a file to the decoder as it is', () async {
      final item = sticker(1);
      final harness = PipelineHarness(known: [item]);
      addTearDown(harness.dispose);
      harness.fetcher.serve(item.key, const FetchedContent.file('/a.webp'));

      harness.attach(item);
      await harness.settle();

      final content = harness.decoder.decodes.single.request.content;
      expect((content as FetchedFile).path, '/a.webp');
    });

    test('uses the newest descriptor the host gave', () async {
      final item = sticker(1, thumbnail: true);
      final harness = PipelineHarness(
        known: [sticker(1)],
        served: [item],
        autoFetch: false,
      );
      addTearDown(harness.dispose);
      harness.pipeline.know(item);

      harness.attach(item);

      expect(
        harness.fetcher.fetches.map((fetch) => fetch.request.part),
        contains(FetchPart.thumbnail),
      );
    });

    test('cancels everything when it is disposed', () async {
      final item = sticker(1);
      final harness = PipelineHarness(known: [item], autoFetch: false);
      harness.attach(item);

      harness.pipeline.dispose();

      expect(harness.fetcher.fetches.single.isCancelled, isTrue);
      harness.scope.dispose();
    });
  });
}

final class _ThrowingFetcher implements ContentFetcher {
  @override
  Future<FetchedContent> fetch(FetchRequest request) =>
      throw StateError('fetcher bug');
}

final class _ThrowingDecoder implements Decoder {
  @override
  AssetTask decode(DecodeRequest request, AssetProgress progress) =>
      throw StateError('decoder bug');
}

final class _GivingUpDecoder implements Decoder {
  @override
  AssetTask decode(DecodeRequest request, AssetProgress progress) {
    progress.cancelled();
    return _NoTask();
  }
}

final class _NoTask implements AssetTask {
  @override
  void cancel() {}
}
