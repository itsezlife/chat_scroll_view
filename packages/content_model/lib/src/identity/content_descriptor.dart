import 'dart:typed_data';

import 'package:content_model/src/identity/content_key.dart';
import 'package:content_model/src/pack/pack.dart';
import 'package:meta/meta.dart';

/// What a piece of content is to the user.
///
/// Drives policy: which panel an item belongs to, whether it can be sent
/// inline, how a composer treats it. It is independent of [MediaForm], which
/// says how the content renders.
///
/// Hosts name kinds from their own data (a mime type plus attributes, a server
/// tag), so the set must tolerate values a host or an older stored record
/// introduces: [fromValue] maps anything it does not know to [unknown].
enum SemanticKind {
  /// A standard unicode emoji.
  unicodeEmoji('unicode_emoji'),

  /// A document-backed emoji that is embedded in text.
  customEmoji('custom_emoji'),

  /// A sticker.
  sticker('sticker'),

  /// A sticker that is positioned over a face or another image.
  mask('mask'),

  /// An animated image or short video clip sent as a message.
  gif('gif'),

  /// A kind this package does not know. The safe default: consumers treat it
  /// as the most conservative option rather than guessing one.
  unknown('unknown');

  const SemanticKind(this.value);

  /// The kind written as [value], or [unknown] when [value] is null or names
  /// no kind.
  ///
  /// Unlike a closed domain enum this never throws: an unrecognised value is
  /// an expected input (a newer host, an older stored record), and degrading
  /// to [unknown] keeps the content usable instead of failing the whole list.
  factory SemanticKind.fromValue(String? value) {
    for (final kind in values) {
      if (kind.value == value) return kind;
    }
    return unknown;
  }

  /// The stable string for storage and host interchange. Separate from the
  /// Dart name so renaming a constant does not change what is persisted.
  final String value;
}

/// How a piece of content renders.
///
/// Selects the asset pipeline and the painter, independent of the
/// [SemanticKind] that says what the content means. Unrecognised host values
/// decode to [unknown] through [fromValue].
enum MediaForm {
  /// Text drawn from a font: a unicode emoji shown as a glyph.
  glyph('glyph'),

  /// A single still image.
  still('still'),

  /// A resolution-independent vector animation.
  vectorAnimation('vector_animation'),

  /// A sequence of frames in an image format (animated WebP, GIF, APNG),
  /// decoded by image codecs.
  ///
  /// Not [video]: decoders are chosen by form, and an image codec cannot read
  /// a video stream, nor a video decoder an image file. One form for both
  /// would let only one of the two adapters be registered.
  animatedImage('animated_image'),

  /// Video-coded media (a WebM or MP4 clip), decoded by a video decoder.
  video('video'),

  /// A form this package does not know. The safe default.
  unknown('unknown');

  const MediaForm(this.value);

  /// The form written as [value], or [unknown] when [value] is null or names
  /// no form. Never throws; see [SemanticKind.fromValue].
  factory MediaForm.fromValue(String? value) {
    for (final form in values) {
      if (form.value == value) return form;
    }
    return unknown;
  }

  /// The stable string for storage and host interchange.
  final String value;
}

/// An opaque host-issued handle to the thumbnail of a piece of content.
///
/// Nothing in this package reads it: a fetcher resolves it, and only the host
/// that issued it knows its structure.
extension type const ThumbnailRef(String value) {}

/// The intrinsic size of the source media in pixels.
///
/// A hint available before the content loads, so a placeholder can reserve the
/// right shape. It is not a layout size.
@immutable
final class ContentSize {
  /// Creates a size; both dimensions must be positive.
  const ContentSize(this.width, this.height)
    : assert(width > 0 && height > 0, 'A ContentSize must be positive.');

  /// Width in pixels.
  final int width;

  /// Height in pixels.
  final int height;

  @override
  bool operator ==(Object other) =>
      other is ContentSize && other.width == width && other.height == height;

  @override
  int get hashCode => Object.hash(width, height);

  @override
  String toString() => 'ContentSize($width x $height)';
}

/// A stand-in for a piece of content known before its content or its
/// thumbnail is fetched: drawn from the first frame the content is on screen.
///
/// - [ContentPreview.raster]: a tiny encoded image (JPEG, PNG, WebP), a few
///   dozen pixels on its long edge, which is blurred when it is drawn.
/// - [ContentPreview.outline]: the shape of the content (a sticker, an emoji)
///   as SVG path data in a view box, drawn as a filled path.
///
/// Both carry plain, expanded data. A data source that receives a compact
/// wire form (an image whose common header was stripped, a compressed path)
/// expands it before it builds the descriptor, so nothing that reads a
/// preview needs to know the wire.
@immutable
sealed class ContentPreview {
  /// A preview of [encoded] image bytes. The preview keeps a read-only copy,
  /// so a later change to [encoded] changes nothing.
  factory ContentPreview.raster(Uint8List encoded) = ContentPreview$Raster;

  /// A preview of the outline [pathData] (SVG path syntax) laid out in
  /// [viewBox].
  const factory ContentPreview.outline(String pathData, ContentSize viewBox) =
      ContentPreview$Outline;

  const ContentPreview._();
}

/// A [ContentPreview] of encoded image bytes.
///
/// A value: equal to another of the same bytes. The content hash is computed
/// once, and the bytes are compared only when it matches.
final class ContentPreview$Raster extends ContentPreview {
  /// A preview of a copy of [encoded].
  ContentPreview$Raster(Uint8List encoded)
    : encoded = Uint8List.fromList(encoded).asUnmodifiableView(),
      _hash = Object.hashAll(encoded),
      super._();

  /// The encoded image, read only.
  final Uint8List encoded;

  final int _hash;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ContentPreview$Raster ||
        other._hash != _hash ||
        other.encoded.length != encoded.length) {
      return false;
    }
    for (var i = 0; i < encoded.length; i++) {
      if (other.encoded[i] != encoded[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => _hash;

  @override
  String toString() => 'ContentPreview.raster(${encoded.length} bytes)';
}

/// A [ContentPreview] of an outline: SVG path data in a view box.
final class ContentPreview$Outline extends ContentPreview {
  /// A preview of [pathData] in [viewBox].
  const ContentPreview$Outline(this.pathData, this.viewBox) : super._();

  /// The outline in SVG path syntax, in the coordinates of [viewBox].
  final String pathData;

  /// The box the path is drawn in; the outline is scaled from it to the
  /// content's box.
  final ContentSize viewBox;

  @override
  bool operator ==(Object other) =>
      other is ContentPreview$Outline &&
      other.pathData == pathData &&
      other.viewBox == viewBox;

  @override
  int get hashCode => Object.hash(pathData, viewBox);

  @override
  String toString() =>
      'ContentPreview.outline(${pathData.length} chars, '
      '$viewBox)';
}

/// What is known about a piece of content, beyond which content it is.
///
/// A descriptor is a [key] plus two orthogonal axes, [semanticKind] and
/// [mediaForm], plus the facts a panel needs before any asset has loaded.
/// Data sources attach descriptors eagerly when they already hold them (a
/// loaded set); a bare [ContentKey] found in message text, recents or a deep
/// link has none until the host resolves it. Whether a descriptor has loaded
/// is therefore a property of the list that carries it, never a field here.
///
/// The axes are not validated against the key: a key says which content, the
/// descriptor says what the host knows about it. Every fact defaults to the
/// conservative value, so a descriptor built from partial host data is valid.
@immutable
final class ContentDescriptor {
  /// Creates a descriptor for [key].
  const ContentDescriptor({
    required this.key,
    this.semanticKind = SemanticKind.unknown,
    this.mediaForm = MediaForm.unknown,
    this.animated = false,
    this.tintable = false,
    this.locked = false,
    this.size,
    this.byteSize,
    this.duration,
    this.streamable = false,
    this.thumbnail,
    this.preview,
    this.spokenName,
    this.shortcode,
    this.pack,
  }) : assert(byteSize == null || byteSize >= 0, 'byteSize is not negative.');

  /// The content this descriptor describes.
  final ContentKey key;

  /// What the content is to the user.
  final SemanticKind semanticKind;

  /// How the content renders.
  final MediaForm mediaForm;

  /// Whether the content moves. Independent of [mediaForm]: a moving item may
  /// still be shown as its first frame only.
  final bool animated;

  /// Whether the content takes the surrounding text colour instead of its own.
  final bool tintable;

  /// Whether using the content is gated, for example behind a subscription.
  /// A locked item is still listed and shown.
  final bool locked;

  /// The source media size, when the host knows it.
  final ContentSize? size;

  /// The size of the content's file in bytes, when the host knows it.
  ///
  /// Read before any byte arrives: a download's progress falls back to it
  /// when the transfer reports no total, the size label shows it, and the
  /// auto-download policy weighs it against its limits (a moving item of
  /// unknown size waits for the user).
  final int? byteSize;

  /// How long the content plays, when the host knows it: the duration label
  /// of a clip.
  final Duration? duration;

  /// Whether the content can play while it downloads (a video whose index
  /// comes first). A streamable video offers play before its download ends.
  final bool streamable;

  /// The thumbnail to show while the content itself loads, when there is one.
  final ThumbnailRef? thumbnail;

  /// The stand-in drawn before the content and its [thumbnail] arrive, when
  /// the data carries one. Without one the cache derives a preview the first
  /// time the content loads, and the surface is clear until then.
  final ContentPreview? preview;

  /// The name read aloud for this content in the active language, when the
  /// data provides one. Absent means the consumer falls back to the content's
  /// plain-text alternative or to no label, never to a guessed name.
  final String? spokenName;

  /// The short text code that stands for this content in typed text, such as
  /// `:grinning:`, when the data provides one. It is the same in every
  /// language, unlike [spokenName]; a panel shows it as a hint for the item.
  final String? shortcode;

  /// The pack the content belongs to, when it was published in one: the
  /// pack a sticker or custom emoji opens. Null for content outside any pack
  /// (a sticker sent on its own, a GIF, a unicode emoji). Not identity: the
  /// key alone says which content this is.
  final PackId? pack;

  @override
  bool operator ==(Object other) =>
      other is ContentDescriptor &&
      other.key == key &&
      other.semanticKind == semanticKind &&
      other.mediaForm == mediaForm &&
      other.animated == animated &&
      other.tintable == tintable &&
      other.locked == locked &&
      other.size == size &&
      other.byteSize == byteSize &&
      other.duration == duration &&
      other.streamable == streamable &&
      other.thumbnail == thumbnail &&
      other.preview == preview &&
      other.spokenName == spokenName &&
      other.shortcode == shortcode &&
      other.pack == pack;

  @override
  int get hashCode => Object.hash(
    key,
    semanticKind,
    mediaForm,
    animated,
    tintable,
    locked,
    size,
    byteSize,
    duration,
    streamable,
    thumbnail,
    preview,
    spokenName,
    shortcode,
    pack,
  );

  @override
  String toString() =>
      'ContentDescriptor($key, ${semanticKind.value}, ${mediaForm.value})';
}
