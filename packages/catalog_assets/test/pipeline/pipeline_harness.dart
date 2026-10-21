import 'dart:typed_data';

import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/testing.dart';
import 'package:content_model/content_model.dart';

const profile = AssetProfile();
const spec = AssetSpec(pixelWidth: 64, pixelHeight: 64);
const firstFrameSpec = AssetSpec(
  pixelWidth: 64,
  pixelHeight: 64,
  variant: AssetVariant.firstFrame,
);

/// The descriptor of sticker [n], with a thumbnail unless [thumbnail] is off.
ContentDescriptor sticker(int n, {bool thumbnail = false}) => ContentDescriptor(
  key: ContentKey.document('sticker-$n'),
  semanticKind: SemanticKind.sticker,
  mediaForm: MediaForm.still,
  thumbnail: thumbnail ? ThumbnailRef('thumb-$n') : null,
);

final bytes = FetchedContent.bytes(Uint8List.fromList(const [1, 2, 3]));

/// A scope over an [AssetPipeline] made of fakes.
final class PipelineHarness {
  PipelineHarness({
    bool autoFetch = true,
    bool autoDecode = true,
    bool firstFrameEarly = false,
    ContentResolver? resolver,
    AssetPipelineLimits limits = const AssetPipelineLimits(),
    Iterable<ContentDescriptor> known = const [],
    Iterable<ContentDescriptor> served = const [],
  }) : fetcher = FakeFetcher(autoRespond: autoFetch),
       decoder = FakeDecoder(
         autoRespond: autoDecode,
         reportFirstFrame: firstFrameEarly,
       ) {
    pipeline = AssetPipeline(
      fetcher: fetcher,
      decoders: DecoderRegistry()..register(MediaForm.still, decoder),
      resolver: resolver,
      limits: limits,
    );
    scope = AssetCacheScope(
      producer: pipeline,
      clock: PlaybackClock(ticks: ManualPlaybackTickSource()),
    );
    for (final descriptor in [...known, ...served]) {
      fetcher.serve(descriptor.key, bytes);
      if (descriptor.thumbnail != null) {
        fetcher.serveThumbnail(descriptor.thumbnail!, bytes);
      }
    }
    known.forEach(pipeline.know);
  }

  final FakeFetcher fetcher;
  final FakeDecoder decoder;
  late final AssetPipeline pipeline;
  late final AssetCacheScope scope;

  AssetBinding attach(ContentDescriptor descriptor, [AssetSpec spec = spec]) =>
      scope.attach(descriptor.key, spec, profile);

  AssetBinding attachKey(ContentKey key, [AssetSpec spec = spec]) =>
      scope.attach(key, spec, profile);

  /// Lets queued microtasks and futures run.
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  void dispose() {
    scope.dispose();
    pipeline.dispose();
  }
}
