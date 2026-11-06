import 'dart:io';

import 'package:catalog_assets/catalog_assets.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/animated_emoji_pack.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/bundled_packs.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/lottie_sticker_pack.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The app bundle as the files under `assets/` on disk.
final class _DiskBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    final file = File(key);
    if (!file.existsSync()) throw FlutterError('Unable to load asset: $key');
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
  final emoji = AnimatedEmojiPack.emoji.first;
  final sticker = LottieStickerPack.stickers.first;

  test('lists the descriptors of every pack', () {
    expect(BundledPacks.descriptors, [
      ...AnimatedEmojiPack.descriptors,
      ...LottieStickerPack.descriptors,
    ]);
  });

  group('the fetcher', () {
    final fetcher = BundledPacks.fetcher(_DiskBundle());

    test('reads an emoji and a sticker from the bundle', () async {
      final emojiContent = await fetcher.fetch(_request(emoji.descriptor));
      final stickerContent = await fetcher.fetch(_request(sticker.descriptor));

      expect(
        (emojiContent as FetchedBytes).bytes,
        File('assets/animated_emoji/${emoji.code}.webp').readAsBytesSync(),
      );
      expect(
        (stickerContent as FetchedBytes).bytes,
        File(sticker.assetPath).readAsBytesSync(),
      );
    });

    test('fails other content, and a thumbnail nobody has, for good', () async {
      const other = ContentDescriptor(key: ContentKey.document('other'));

      for (final request in [
        _request(other),
        _request(sticker.descriptor, part: FetchPart.thumbnail),
      ]) {
        await expectLater(
          fetcher.fetch(request),
          throwsA(
            isA<FetchFailure>().having(
              (failure) => failure.kind,
              'kind',
              AssetFailureKind.permanent,
            ),
          ),
        );
      }
    });
  });

  test(
    'the resolver describes the keys of every pack and nothing else',
    () async {
      final found = await BundledPacks.resolver().resolve([
        emoji.key,
        sticker.key,
        const ContentKey.document('other'),
      ]);

      expect(found, {
        emoji.key: emoji.descriptor,
        sticker.key: sticker.descriptor,
      });
    },
  );
}
