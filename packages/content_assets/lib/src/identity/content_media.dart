import 'package:content_model/content_model.dart';
import 'package:mpx_core/mpx_core.dart';

/// The [MediaKey] a [ContentKey] is cached and fetched under.
///
/// The mapping is total and one-to-one, so a media key read back from the
/// cache names exactly one content key ([MediaKeyContent.contentKey]):
///
/// | Content key | Media key |
/// | --- | --- |
/// | `document(id)` | `remote(id)`: an id the host's own backend issues |
/// | `external(id)` | `external('external:<id>')`, the content key's encoded form |
/// | `unicode(sequence)` | `external('unicode:<code points>')`, likewise |
///
/// External ids carry their content key's encoded form, not the bare id, so
/// that no external id can name the same media key as a glyph. A glyph's
/// media key is only its binding's identity: glyphs are drawn from the glyph
/// atlas (`ContentAssetScope`), never fetched or decoded.
extension ContentKeyMedia on ContentKey {
  /// The media key of this content.
  MediaKey get mediaKey => switch (this) {
    ContentKey$Document(:final id) => MediaKey.remote(id),
    ContentKey$External() || ContentKey$Unicode() => MediaKey.external(encoded),
  };
}

/// The [ContentKey] a [MediaKey] stands for: the inverse of
/// [ContentKeyMedia.mediaKey].
extension MediaKeyContent on MediaKey {
  /// The content key of this media, or null for media the chat never names
  /// (a local key, or an external id that is not an encoded content key).
  ContentKey? get contentKey => switch (this) {
    MediaKey$Remote(:final id) => ContentKey.document(id),
    MediaKey$External(:final id) => switch (ContentKey.tryParse(id)) {
      final key? when key is! ContentKey$Document => key,
      _ => null,
    },
    MediaKey$Local() => null,
  };
}

/// The [MediaDescriptor] the media core reads for a [ContentDescriptor].
extension ContentDescriptorMedia on ContentDescriptor {
  /// What the media core needs to fetch and decode this content, or null for
  /// a glyph, which it never decodes.
  ///
  /// The core reads the key, the kind, whether it moves, the pixel size and
  /// the thumbnail; the content facts (semantic kind, tint, pack, spoken name)
  /// stay with the chat.
  MediaDescriptor? get mediaDescriptor {
    final kind = switch (mediaForm) {
      MediaForm.glyph => null,
      MediaForm.still => MediaKind.still,
      MediaForm.vectorAnimation => MediaKind.vectorAnimation,
      MediaForm.animatedImage => MediaKind.animatedImage,
      MediaForm.video => MediaKind.video,
      MediaForm.unknown => MediaKind.unknown,
    };
    if (kind == null) return null;
    return MediaDescriptor(
      key: key.mediaKey,
      kind: kind,
      animated: animated,
      dimensions: switch (size) {
        ContentSize(:final width, :final height) when width > 0 && height > 0 =>
          MediaDimensions(width, height),
        _ => null,
      },
      thumbnail: switch (thumbnail) {
        final ref? => MediaThumbnailRef(ref.value),
        null => null,
      },
    );
  }
}

/// A [MediaResolver] over the chat's [ContentResolver]: bare media keys are
/// resolved as the content keys they stand for.
///
/// Keys the chat never names, and content that resolves to a glyph, are left
/// out, as unknown keys are.
final class ContentMediaResolver implements MediaResolver {
  /// Resolves through [content].
  const ContentMediaResolver(this.content);

  /// The chat's resolver.
  final ContentResolver content;

  @override
  Future<Map<MediaKey, MediaDescriptor>> resolve(
    Iterable<MediaKey> keys,
  ) async {
    final asked = <ContentKey, MediaKey>{};
    for (final key in keys) {
      if (key.contentKey case final content?) asked[content] = key;
    }
    if (asked.isEmpty) return const {};
    final found = await content.resolve(asked.keys);
    final resolved = <MediaKey, MediaDescriptor>{};
    for (final descriptor in found.values) {
      final media = descriptor.mediaDescriptor;
      if (media != null && asked[descriptor.key] == media.key) {
        resolved[media.key] = media;
      }
    }
    return resolved;
  }
}
