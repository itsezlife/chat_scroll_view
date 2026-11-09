import 'package:chat_scroll_view_example/src/features/chat/data/bundled_pack_source.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/foundation.dart';

/// One sticker of the [StaticStickerPack]: a PNG in the app bundle.
@immutable
final class StaticSticker implements BundledItem {
  const StaticSticker._(this.name, this.spokenName);

  /// The file's name, without its extension.
  final String name;

  /// The name read aloud for it.
  final String spokenName;

  /// Its content identity: a document key under the pack's own prefix, so its
  /// cache entry and recents slot never meet another pack's.
  @override
  ContentKey get key =>
      ContentKey.document('${StaticStickerPack._keyPrefix}$name');

  /// What the pipeline needs to make it. What makes it a sticker is its
  /// semantic kind; its media form is a plain still, decoded by the same codec
  /// as any image.
  @override
  ContentDescriptor get descriptor => ContentDescriptor(
    key: key,
    semanticKind: SemanticKind.sticker,
    mediaForm: MediaForm.still,
    animated: false,
    size: const ContentSize(
      StaticStickerPack._pixelSize,
      StaticStickerPack._pixelSize,
    ),
    spokenName: spokenName,
    pack: StaticStickerPack.packId,
  );

  @override
  String get assetPath => 'assets/static_stickers/$name.png';
}

/// The demo's pack of static stickers, authored for it: simple shapes on a
/// transparent 512 x 512 canvas with soft edges (`assets/static_stickers/`).
///
/// It stands in for content a real host fetches from its backend, like the
/// other bundled packs: [source] publishes the pack as a collection,
/// [descriptors] are what the host tells its asset pipeline, and
/// `BundledPacks` reads [StaticSticker.assetPath] from the bundle. It needs no
/// native library: a still is decoded by the engine's image codecs.
abstract final class StaticStickerPack {
  /// The collection the pack is listed as.
  static const CollectionId id = CollectionId.set('demo_still');

  /// The pack's title.
  static const String title = 'Demo static stickers';

  /// The pack each sticker names: the same text as [id].
  static const PackId packId = PackId('demo_still');

  /// The pack, as the host's pack source serves it.
  static Pack get pack => Pack(
    id: packId,
    kind: PackKind.stickers,
    title: title,
    items: descriptors.toList(),
  );

  static const String _keyPrefix = 'demo-still:';

  static const int _pixelSize = 512;

  /// The stickers, in the order the pack shows them. Each has a file in
  /// `assets/static_stickers/`; the two are kept by hand.
  static const List<StaticSticker> stickers = [
    StaticSticker._('sun', 'a sun'),
    StaticSticker._('moon', 'a crescent moon'),
    StaticSticker._('kite', 'a kite'),
    StaticSticker._('cloud', 'a cloud'),
  ];

  static final Map<ContentKey, StaticSticker> _byKey = {
    for (final sticker in stickers) sticker.key: sticker,
  };

  /// The sticker of [key], or null for content that is not the pack's.
  static StaticSticker? of(ContentKey key) => _byKey[key];

  /// The descriptor of every sticker, for the host's asset pipeline.
  static Iterable<ContentDescriptor> get descriptors =>
      stickers.map((sticker) => sticker.descriptor);

  /// A source that lists the pack, loaded from the start.
  static CollectionSource source() =>
      BundledPackSource(id: id, title: title, items: stickers);
}
