import 'package:content_model/src/identity/content_descriptor.dart';
import 'package:meta/meta.dart';

/// What a media item of a message is shown as.
///
/// Set by the host, which knows how the item was sent: a photo sent as a
/// file is a [file]. [fromDescriptor] gives a default for a host that does
/// not care. Photos, videos and animations draw as boxes; files and custom
/// kinds draw as rows.
///
/// Open to kinds this package does not know, as [SemanticKind] and
/// [MediaForm] are: [fromValue] reads an unknown string as [custom] with
/// that tag rather than failing, so a newer host or an older stored record
/// still shows its item (as a file row). Equal by [value].
@immutable
final class MediaItemKind {
  const MediaItemKind._(this.value);

  /// A kind this package does not name, written as [tag].
  ///
  /// [tag] is not empty and is none of the built-in kinds' values.
  const MediaItemKind.custom(String tag)
    : assert(tag != '', 'A custom kind needs a tag.'),
      assert(
        tag != 'photo' && tag != 'video' && tag != 'animation' && tag != 'file',
        'A custom kind does not reuse a built-in value.',
      ),
      value = tag;

  /// The kind written as [value]: a built-in kind, or [custom] with [value]
  /// as its tag. A missing or empty value is a [file].
  ///
  /// Never throws; an unknown value is an expected input.
  factory MediaItemKind.fromValue(String? value) {
    if (value == null || value.isEmpty) return file;
    for (final kind in builtIns) {
      if (kind.value == value) return kind;
    }
    return MediaItemKind.custom(value);
  }

  /// The default kind of [descriptor]'s content.
  ///
  /// A GIF is an [animation] whatever its form (a GIF is often sent as a
  /// video clip). Otherwise the media form decides when it names a still,
  /// an animated image or a video; failing that, the MIME type's class
  /// (`image/gif` is an animation, `image/*` a photo, `video/*` a video).
  /// Anything else, or nothing known, is a [file].
  factory MediaItemKind.fromDescriptor(ContentDescriptor descriptor) {
    if (descriptor.semanticKind == SemanticKind.gif) return animation;
    switch (descriptor.mediaForm) {
      case MediaForm.still || MediaForm.vectorImage:
        return photo;
      case MediaForm.animatedImage:
        return animation;
      case MediaForm.video:
        return video;
      case MediaForm.glyph || MediaForm.vectorAnimation || MediaForm.unknown:
        break;
    }
    return _fromMimeType(descriptor.mimeType);
  }

  static MediaItemKind _fromMimeType(String? mimeType) {
    if (mimeType == null) return file;
    final type = mimeType.split(';').first.trim().toLowerCase();
    if (type == 'image/gif') return animation;
    return switch (type.split('/')) {
      ['image', _] => photo,
      ['video', _] => video,
      _ => file,
    };
  }

  /// A still image.
  static const photo = MediaItemKind._('photo');

  /// A video clip.
  static const video = MediaItemKind._('video');

  /// A GIF: a short silent loop, whether an animated image or a video clip.
  static const animation = MediaItemKind._('animation');

  /// A file, shown as a row with its name and size.
  static const file = MediaItemKind._('file');

  /// The kinds this package names, in a fixed order.
  static const List<MediaItemKind> builtIns = [photo, video, animation, file];

  /// The stable string for storage and host interchange.
  final String value;

  /// Whether this is a [custom] kind rather than a built-in one.
  bool get isCustom => !builtIns.contains(this);

  /// Whether this is a picture: a [photo], [video] or [animation], drawn as
  /// a box of its own aspect and paged together in a viewer. A [file] or a
  /// custom kind is not.
  bool get isPicture => this == photo || this == video || this == animation;

  /// Whether items of this kind play: a [video] or an [animation].
  bool get plays => this == video || this == animation;

  @override
  bool operator ==(Object other) =>
      other is MediaItemKind && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() =>
      isCustom ? 'MediaItemKind.custom($value)' : 'MediaItemKind.$value';
}
