import 'package:catalog_assets/catalog_assets.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/animated_emoji_pack.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/bundle_fetcher.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/lottie_sticker_pack.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/services.dart';

/// The packs the app bundles, as the host's asset pipeline and its recents see
/// them: one fetcher, one resolver and one list of descriptors over all of
/// them, so a pack added here is served, described and known in one place.
abstract final class BundledPacks {
  /// The descriptor of every item of every pack, for the asset pipeline.
  static Iterable<ContentDescriptor> get descriptors => [
    ...AnimatedEmojiPack.descriptors,
    ...LottieStickerPack.descriptors,
  ];

  /// A fetcher that reads every pack's files from [bundle].
  static ContentFetcher fetcher(AssetBundle bundle) => BundleFetcher(
    bundle,
    pathOf: (key) =>
        AnimatedEmojiPack.of(key)?.assetPath ??
        LottieStickerPack.of(key)?.assetPath,
  );

  /// A resolver that knows the keys of every pack and nothing else.
  static ContentResolver resolver() => const _PacksResolver();
}

final class _PacksResolver implements ContentResolver {
  const _PacksResolver();

  @override
  Future<Map<ContentKey, ContentDescriptor>> resolve(
    Iterable<ContentKey> keys,
  ) async => {
    for (final key in keys)
      key:
          ?(AnimatedEmojiPack.of(key)?.descriptor ??
          LottieStickerPack.of(key)?.descriptor),
  };
}
