import 'package:catalog_assets/catalog_assets.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:listen/listen.dart' as listen;

/// One emoji of the [AnimatedEmojiPack]: an animated WebP in the app bundle.
@immutable
final class AnimatedEmoji {
  const AnimatedEmoji._(this.code, this.name);

  /// The code points, as Noto names its files: lower-case hex joined by `_`.
  final String code;

  /// The name read aloud for it.
  final String name;

  /// The unicode sequence it animates: what it is as plain text.
  String get sequence => String.fromCharCodes([
    for (final point in code.split('_')) int.parse(point, radix: 16),
  ]);

  /// Its content identity. A document key, not the unicode one: the animated
  /// emoji is other content than the glyph it stands for, and the two must
  /// never share a cache entry or a recents slot.
  ContentKey get key =>
      ContentKey.document('${AnimatedEmojiPack._keyPrefix}$code');

  /// What the pipeline needs to make it.
  ContentDescriptor get descriptor => ContentDescriptor(
    key: key,
    semanticKind: SemanticKind.customEmoji,
    mediaForm: MediaForm.animatedImage,
    animated: true,
    size: const ContentSize(
      AnimatedEmojiPack._pixelSize,
      AnimatedEmojiPack._pixelSize,
    ),
    spokenName: name,
  );

  String get _assetPath => 'assets/animated_emoji/$code.webp';
}

/// The demo's one pack of animated emoji: Google's Noto Animated Emoji,
/// bundled as 96 px animated WebP (`tool/fetch_noto_animated_emoji.py` makes
/// the files; the credit CC BY 4.0 asks for is in their `LICENSE.md`).
///
/// It stands in for content a real host fetches from its backend: [source]
/// publishes the pack as a collection, [descriptors] are what the host tells
/// its asset pipeline, [resolver] describes the pack's keys found bare (in the
/// recents), and [fetcher] reads the files from the bundle where a real one
/// would download them.
abstract final class AnimatedEmojiPack {
  /// The collection the pack is listed as.
  static const CollectionId id = CollectionId.set('noto_animated_emoji');

  /// The pack's title, as its publisher names it.
  static const String title = 'Noto Animated Emoji';

  static const String _keyPrefix = 'noto-animated:';

  static const int _pixelSize = 96;

  /// The emoji, in the order the pack shows them. Each has a file the fetch
  /// script writes; the two lists are kept by hand.
  static const List<AnimatedEmoji> emoji = [
    AnimatedEmoji._('1f600', 'smile'),
    AnimatedEmoji._('1f604', 'grin'),
    AnimatedEmoji._('1f602', 'joy'),
    AnimatedEmoji._('1f923', 'rolling on the floor laughing'),
    AnimatedEmoji._('1f60a', 'blush'),
    AnimatedEmoji._('1f607', 'innocent'),
    AnimatedEmoji._('1f643', 'upside-down face'),
    AnimatedEmoji._('1f609', 'wink'),
    AnimatedEmoji._('1f60d', 'heart eyes'),
    AnimatedEmoji._('1f970', 'smiling face with hearts'),
    AnimatedEmoji._('1f618', 'kissing heart'),
    AnimatedEmoji._('1f61c', 'winking tongue'),
    AnimatedEmoji._('1f92a', 'zany face'),
    AnimatedEmoji._('1f60e', 'sunglasses'),
    AnimatedEmoji._('1f913', 'nerd face'),
    AnimatedEmoji._('1f973', 'partying face'),
    AnimatedEmoji._('1f929', 'star-struck'),
    AnimatedEmoji._('1f914', 'thinking face'),
    AnimatedEmoji._('1f644', 'rolling eyes'),
    AnimatedEmoji._('1f62c', 'grimacing'),
    AnimatedEmoji._('1f631', 'screaming'),
    AnimatedEmoji._('1f62d', 'loudly crying'),
    AnimatedEmoji._('1f621', 'rage'),
    AnimatedEmoji._('1f92f', 'mind blown'),
    AnimatedEmoji._('1f971', 'yawn'),
    AnimatedEmoji._('1f44d', 'thumbs up'),
    AnimatedEmoji._('1f64f', 'folded hands'),
    AnimatedEmoji._('1f525', 'fire'),
    AnimatedEmoji._('2728', 'sparkles'),
    AnimatedEmoji._('1f389', 'party popper'),
    AnimatedEmoji._('2764_fe0f', 'red heart'),
    AnimatedEmoji._('1f680', 'rocket'),
  ];

  static final Map<ContentKey, AnimatedEmoji> _byKey = {
    for (final item in emoji) item.key: item,
  };

  /// The emoji of [key], or null for content that is not the pack's.
  static AnimatedEmoji? of(ContentKey key) => _byKey[key];

  // Without the variation selector: a message typed on a keyboard that omits
  // it ("\u2764") and one that adds it ("\u2764\uFE0F") are the same emoji.
  static final Map<String, ContentKey> _stickerBySequence = {
    for (final item in emoji) _withoutSelector(item.sequence): item.key,
  };

  static String _withoutSelector(String sequence) =>
      sequence.replaceAll('\uFE0F', '');

  /// The animated document a lone unicode emoji [key] is shown as (the host's
  /// `unicode` to `document` map for `ChatEmojiBody.sticker`), or null when the
  /// pack has none for it, and for content that is not a unicode emoji.
  static ContentKey? stickerFor(ContentKey key) => switch (key) {
    ContentKey$Unicode(:final sequence) =>
      _stickerBySequence[_withoutSelector(sequence)],
    _ => null,
  };

  /// The descriptor of every emoji, for the host's asset pipeline.
  static Iterable<ContentDescriptor> get descriptors =>
      emoji.map((item) => item.descriptor);

  /// A source that lists the pack, loaded from the start: everything it holds
  /// is in the bundle, so there is nothing to wait for.
  static CollectionSource source() => _PackSource();

  /// A resolver that knows the pack's emoji and nothing else.
  static ContentResolver resolver() => const _PackResolver();

  /// A fetcher that reads the pack's files from [bundle].
  static ContentFetcher fetcher(AssetBundle bundle) => _BundleFetcher(bundle);
}

final class _PackSource implements CollectionSource {
  final listen.ValueNotifier<List<Collection>> _collections =
      listen.ValueNotifier(
        List.unmodifiable([
          Collection(
            id: AnimatedEmojiPack.id,
            metadata: const CollectionMetadata(
              title: AnimatedEmojiPack.title,
              flags: CollectionFlags.installed,
            ),
            contents: CollectionContents.loaded([
              for (final item in AnimatedEmojiPack.emoji)
                CollectionItem.described(item.descriptor),
            ]),
          ),
        ]),
      );

  @override
  listen.ValueListenable<List<Collection>> get collections => _collections;

  // Loaded from the start, with no page after the first.
  @override
  Future<void> load(CollectionId id) async {}

  @override
  Future<void> loadMore(CollectionId id) async {}

  @override
  void dispose() => _collections.dispose();
}

/// Describes the pack's keys; any other key is unknown content.
final class _PackResolver implements ContentResolver {
  const _PackResolver();

  @override
  Future<Map<ContentKey, ContentDescriptor>> resolve(
    Iterable<ContentKey> keys,
  ) async => {
    for (final key in keys) key: ?AnimatedEmojiPack.of(key)?.descriptor,
  };
}

/// Reads the pack's files from an asset bundle.
///
/// A bundle read cannot be stopped, so a cancelled fetch still completes
/// with its bytes, which the pipeline drops; a file is about 110 KB. A key
/// that is not the pack's, or a file the bundle lacks, is missing content: a
/// permanent failure. The pack has no thumbnails, so none is asked for.
final class _BundleFetcher implements ContentFetcher {
  _BundleFetcher(this._bundle);

  final AssetBundle _bundle;

  @override
  Future<FetchedContent> fetch(FetchRequest request) async {
    final item = AnimatedEmojiPack.of(request.descriptor.key);
    if (item == null || request.part == FetchPart.thumbnail) {
      throw FetchFailure.permanent(
        'not in the bundled pack: ${request.descriptor.key} '
        '(${request.part.name})',
      );
    }
    final ByteData data;
    try {
      data = await _bundle.load(item._assetPath);
      // A bundle reports a file it lacks as a FlutterError and offers no way
      // to ask first.
      // ignore: avoid_catching_errors
    } on FlutterError catch (error) {
      // A bundle does not gain files at run time, so retrying will not help.
      // Anything else is a bug, and stays one.
      throw FetchFailure.permanent('missing ${item._assetPath}', error);
    }
    return FetchedContent.bytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
  }
}
