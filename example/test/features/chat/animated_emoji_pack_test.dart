import 'dart:async';
import 'dart:io';

import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/testing.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/animated_emoji_pack.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_decoder/image_decoder.dart';

/// The app bundle as the files under `assets/` on disk.
final class _DiskBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    final file = File(key);
    if (!file.existsSync()) throw StateError('no asset $key');
    return ByteData.sublistView(await file.readAsBytes());
  }
}

FetchRequest _request(ContentDescriptor descriptor, {FetchPart? part}) =>
    FetchRequest(
      descriptor: descriptor,
      part: part ?? FetchPart.content,
      priority: AssetPriority.visible,
      cancellation: CancellationToken(),
    );

void main() {
  test('every emoji of the pack has its file in the bundle', () {
    for (final item in AnimatedEmojiPack.emoji) {
      expect(
        File('assets/animated_emoji/${item.code}.webp').existsSync(),
        isTrue,
        reason: '${item.code} is listed; run tool/fetch_noto_animated_emoji.py',
      );
    }
    expect(File('assets/animated_emoji/LICENSE.md').existsSync(), isTrue);
  });

  test('every emoji is its own content and reads as its unicode emoji', () {
    final keys = {for (final item in AnimatedEmojiPack.emoji) item.key};
    expect(keys, hasLength(AnimatedEmojiPack.emoji.length));
    expect(AnimatedEmojiPack.of(const ContentKey.document('other')), isNull);
    final heart = AnimatedEmojiPack.emoji.singleWhere(
      (item) => item.code == '2764_fe0f',
    );
    expect(heart.sequence, '❤️');
    expect(AnimatedEmojiPack.of(heart.key), same(heart));
  });

  test('the source lists the pack loaded, every item described', () {
    final source = AnimatedEmojiPack.source();
    addTearDown(source.dispose);

    final collection = source.collections.value.single;
    expect(collection.id, AnimatedEmojiPack.id);
    final contents = collection.contents as CollectionContents$Loaded;
    expect([
      for (final item in contents.items) item.descriptor,
    ], AnimatedEmojiPack.descriptors.toList());
    expect(contents.nextPageToken, isNull);
  });

  test('the resolver describes the pack\'s emoji and nothing else', () async {
    final rocket = AnimatedEmojiPack.emoji.last;

    final found = await AnimatedEmojiPack.resolver().resolve([
      rocket.key,
      const ContentKey.document('other'),
    ]);

    expect(found, {rocket.key: rocket.descriptor});
  });

  group('the fetcher', () {
    final fetcher = AnimatedEmojiPack.fetcher(_DiskBundle());

    test('reads an emoji of the pack from the bundle', () async {
      final item = AnimatedEmojiPack.emoji.first;

      final content = await fetcher.fetch(_request(item.descriptor));

      expect(
        (content as FetchedBytes).bytes,
        File('assets/animated_emoji/${item.code}.webp').readAsBytesSync(),
      );
    });

    test('fails content that is not the pack\'s, for good', () async {
      const other = ContentDescriptor(key: ContentKey.document('other'));

      await expectLater(
        fetcher.fetch(_request(other)),
        throwsA(
          isA<FetchFailure>().having(
            (failure) => failure.kind,
            'kind',
            AssetFailureKind.permanent,
          ),
        ),
      );
    });
  });

  test('an emoji of the pack plays through the pipeline', () async {
    final pipeline = AssetPipeline(
      fetcher: AnimatedEmojiPack.fetcher(_DiskBundle()),
      decoders: DecoderRegistry()
        ..register(MediaForm.video, const ImageCodecDecoder()),
    );
    AnimatedEmojiPack.descriptors.forEach(pipeline.know);
    // No scheduler in a plain test: the clock ticks by hand.
    final scope = AssetCacheScope(
      producer: pipeline,
      clock: PlaybackClock(ticks: ManualPlaybackTickSource()),
    );
    addTearDown(() {
      scope.dispose();
      pipeline.dispose();
    });

    final binding = scope.attach(
      AnimatedEmojiPack.emoji.first.key,
      const AssetSpec(pixelWidth: 96, pixelHeight: 96),
      const AssetProfile(animate: true),
    );
    addTearDown(binding.detach);
    final full = Completer<void>();
    binding.addListener(() {
      if (binding.readiness.stage == AssetStage.full && !full.isCompleted) {
        full.complete();
      }
    });
    await full.future.timeout(const Duration(seconds: 10));

    expect(binding.paintable.isAnimated, isTrue);
    expect(binding.isPlaying, isTrue);
    expect(binding.lastError, isNull);
  });
}
