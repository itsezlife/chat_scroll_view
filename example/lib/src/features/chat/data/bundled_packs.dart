import 'package:catalog_assets/catalog_assets.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/animated_emoji_pack.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/bundle_fetcher.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/bundled_pack_source.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/lottie_sticker_pack.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/static_sticker_pack.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/video_sticker_pack.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/services.dart';

/// What the host knows of a piece of content from its key: the bundled packs
/// answer for theirs, and a host with content from elsewhere (a feed, a local
/// corpus) answers for that too. Null for a key it cannot describe.
typedef DescribeContent = ContentDescriptor? Function(ContentKey key);

/// The packs the app bundles, as the host's asset pipeline and its recents see
/// them: one lookup, one fetcher, one resolver and one list of descriptors over
/// all of them, so a pack added here is served, described and known in one
/// place.
abstract final class BundledPacks {
  /// The descriptor of every item of every pack, for the asset pipeline.
  static Iterable<ContentDescriptor> get descriptors => [
    ...AnimatedEmojiPack.descriptors,
    ...LottieStickerPack.descriptors,
    ...StaticStickerPack.descriptors,
    ...VideoStickerPack.descriptors,
  ];

  /// The item of [key] in any pack, or null for content that is not bundled.
  static BundledItem? of(ContentKey key) =>
      AnimatedEmojiPack.of(key) ??
      LottieStickerPack.of(key) ??
      StaticStickerPack.of(key) ??
      VideoStickerPack.of(key);

  /// The descriptor of the item of [key] in any pack, or null: a
  /// [DescribeContent] over the bundled packs alone.
  static ContentDescriptor? describe(ContentKey key) => of(key)?.descriptor;

  /// A fetcher that reads every pack's files from [bundle].
  static ContentFetcher fetcher(AssetBundle bundle) =>
      BundleFetcher(bundle, pathOf: (key) => of(key)?.assetPath);

  /// A resolver that knows the keys of every pack and nothing else.
  static ContentResolver resolver() => const _PacksResolver();
}

final class _PacksResolver implements ContentResolver {
  const _PacksResolver();

  @override
  Future<Map<ContentKey, ContentDescriptor>> resolve(
    Iterable<ContentKey> keys,
  ) async => {for (final key in keys) key: ?BundledPacks.of(key)?.descriptor};
}
