import 'package:content_model/content_model.dart';
import 'package:flutter/foundation.dart';
import 'package:listen/listen.dart' as listen;

/// One sticker of the [LottieStickerPack]: a Lottie file in the app bundle.
@immutable
final class LottieSticker {
  const LottieSticker._(this.name, this.spokenName);

  /// The file's name, without its extension.
  final String name;

  /// The name read aloud for it.
  final String spokenName;

  /// Its content identity: a document key under the pack's own prefix, so its
  /// cache entry and recents slot never meet another pack's.
  ContentKey get key =>
      ContentKey.document('${LottieStickerPack._keyPrefix}$name');

  /// What the pipeline needs to make it. The decoder registered for
  /// [MediaForm.vectorAnimation] draws it; without one it keeps its
  /// placeholder.
  ContentDescriptor get descriptor => ContentDescriptor(
    key: key,
    semanticKind: SemanticKind.sticker,
    mediaForm: MediaForm.vectorAnimation,
    animated: true,
    size: const ContentSize(
      LottieStickerPack._pixelSize,
      LottieStickerPack._pixelSize,
    ),
    spokenName: spokenName,
  );

  /// Where the bundle holds the file.
  String get assetPath => 'assets/lottie_stickers/$name.json';
}

/// The demo's pack of Lottie stickers, authored for it: shape layers with
/// solid fills and position, scale and rotation keyframes, 512 x 512 at 60 fps
/// over 120 frames (`assets/lottie_stickers/`).
///
/// It stands in for content a real host fetches from its backend, as
/// `AnimatedEmojiPack` does: [source] publishes the pack as a collection,
/// [descriptors] are what the host tells its asset pipeline, [resolver]
/// describes the pack's keys found bare (in the recents), and the bundle
/// fetcher of the app reads [LottieSticker.assetPath].
abstract final class LottieStickerPack {
  /// The collection the pack is listed as.
  static const CollectionId id = CollectionId.set('demo_lottie');

  /// The pack's title.
  static const String title = 'Demo Lottie stickers';

  static const String _keyPrefix = 'demo-lottie:';

  static const int _pixelSize = 512;

  /// The stickers, in the order the pack shows them. Each has a file in
  /// `assets/lottie_stickers/`; the two are kept by hand.
  static const List<LottieSticker> stickers = [
    LottieSticker._('bounce', 'bouncing ball'),
    LottieSticker._('star', 'turning star'),
    LottieSticker._('heart', 'beating heart'),
    LottieSticker._('dots', 'hopping dots'),
  ];

  static final Map<ContentKey, LottieSticker> _byKey = {
    for (final sticker in stickers) sticker.key: sticker,
  };

  /// The sticker of [key], or null for content that is not the pack's.
  static LottieSticker? of(ContentKey key) => _byKey[key];

  /// The descriptor of every sticker, for the host's asset pipeline.
  static Iterable<ContentDescriptor> get descriptors =>
      stickers.map((sticker) => sticker.descriptor);

  /// A source that lists the pack, loaded from the start: everything it holds
  /// is in the bundle, so there is nothing to wait for.
  static CollectionSource source() => _PackSource();

  /// A resolver that knows the pack's stickers and nothing else.
  static ContentResolver resolver() => const _PackResolver();
}

final class _PackSource implements CollectionSource {
  final listen.ValueNotifier<List<Collection>> _collections =
      listen.ValueNotifier(
        List.unmodifiable([
          Collection(
            id: LottieStickerPack.id,
            metadata: const CollectionMetadata(
              title: LottieStickerPack.title,
              flags: CollectionFlags.installed,
            ),
            contents: CollectionContents.loaded([
              for (final sticker in LottieStickerPack.stickers)
                CollectionItem.described(sticker.descriptor),
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
    for (final key in keys) key: ?LottieStickerPack.of(key)?.descriptor,
  };
}
