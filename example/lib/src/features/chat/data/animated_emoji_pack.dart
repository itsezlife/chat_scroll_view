import 'package:chat_scroll_view_example/src/features/chat/data/bundled_pack_source.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/foundation.dart';

/// One emoji of the [AnimatedEmojiPack]: an animated WebP in the app bundle.
@immutable
final class AnimatedEmoji implements BundledItem {
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
  @override
  ContentKey get key =>
      ContentKey.document('${AnimatedEmojiPack._keyPrefix}$code');

  @override
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

  @override
  String get assetPath => 'assets/animated_emoji/$code.webp';
}

/// The demo's one pack of animated emoji: Google's Noto Animated Emoji,
/// bundled as 96 px animated WebP (`tool/fetch_noto_animated_emoji.py` makes
/// the files; the credit CC BY 4.0 asks for is in their `LICENSE.md`).
///
/// It stands in for content a real host fetches from its backend: [source]
/// publishes the pack as a collection and [descriptors] are what the host tells
/// its asset pipeline. `BundledPacks` reads the files from the bundle where a
/// real host would download them, and describes the pack's keys found bare (in
/// the recents).
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
  static CollectionSource source() =>
      BundledPackSource(id: id, title: title, items: emoji);
}
