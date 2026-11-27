import 'package:content_model/src/identity/content_descriptor.dart';
import 'package:content_model/src/rich_text/rich_text.dart';
import 'package:meta/meta.dart';

/// The page a link preview shows: what a resolver or the sender found at a
/// URL.
///
/// A value of facts, every one optional but the [url]: a page as a backend
/// or a client-side fetch returns it, partial or full. Which facts a card
/// draws, and whether its media is small or large, is the display policy's
/// call, not the page's; the message's choices about the preview are its
/// [LinkPreviewOptions].
///
/// [photo] and [media] are descriptors, so the page's pictures load through
/// the same content path as a message's own media.
@immutable
final class LinkPreview {
  /// A page at [url].
  const LinkPreview({
    required this.url,
    this.displayUrl,
    this.type,
    this.siteName,
    this.title,
    this.author,
    this.description = RichText.empty,
    this.photo,
    this.media,
    this.duration,
    this.hasLargeMedia,
  });

  /// The page's address.
  final Uri url;

  /// The address as the card shows it, when the source gives one (usually
  /// without the scheme).
  final String? displayUrl;

  /// The kind of page, as the source names it (`article`, `photo`,
  /// `video`, a profile...).
  ///
  /// Opaque: the set is the backend's and grows without a release, so it is
  /// a string, not an enum. A display policy compares it with the types a
  /// host lists (the ones drawn small, for instance).
  final String? type;

  /// The site's name.
  final String? siteName;

  /// The page's title.
  final String? title;

  /// The page's author.
  final String? author;

  /// The page's description, formatted; empty when there is none.
  final RichText description;

  /// The page's picture.
  final ContentDescriptor? photo;

  /// The page's playable or downloadable content: a video, an animation or
  /// a file.
  final ContentDescriptor? media;

  /// How long [media] plays, when the source says.
  final Duration? duration;

  /// The source's hint that the page's media reads best large; null when the
  /// source gives no hint, which a policy that reads the hint treats
  /// differently from an explicit `false`.
  final bool? hasLargeMedia;

  @override
  bool operator ==(Object other) =>
      other is LinkPreview &&
      other.url == url &&
      other.displayUrl == displayUrl &&
      other.type == type &&
      other.siteName == siteName &&
      other.title == title &&
      other.author == author &&
      other.description == description &&
      other.photo == photo &&
      other.media == media &&
      other.duration == duration &&
      other.hasLargeMedia == hasLargeMedia;

  @override
  int get hashCode => Object.hash(
    url,
    displayUrl,
    type,
    siteName,
    title,
    author,
    description,
    photo,
    media,
    duration,
    hasLargeMedia,
  );

  // The host only: a URL's path, a title or a description is user content
  // and has no place in a log line.
  @override
  String toString() => 'LinkPreview(${url.host}, type: $type)';
}

/// How large a link preview's media is drawn.
///
/// Tolerant like the descriptor's enums: a value a newer client writes reads
/// as [auto] through [fromValue].
enum LinkPreviewMedia {
  /// The display policy's default for the page and the platform.
  auto('auto'),

  /// Small, beside the card's text.
  small('small'),

  /// Large, under the card's text.
  large('large');

  const LinkPreviewMedia(this.value);

  /// The size written as [value], or [auto] when [value] is null or names no
  /// size. Never throws.
  factory LinkPreviewMedia.fromValue(String? value) {
    for (final media in values) {
      if (media.value == value) return media;
    }
    return auto;
  }

  /// The stable string for the wire and the draft.
  final String value;
}

/// The message's choices about its link preview: which URL, how large, or
/// none at all.
///
/// These travel with the message and its draft (ADR 034's amendment); the
/// page itself is a [LinkPreview]. Where the card sits, above or below the
/// text, is not an option but the message's `invertMedia` flag. The
/// composer's dismissal state is not here either: it is composer-only and
/// kept in the draft record, so the sent value cannot carry it.
@immutable
final class LinkPreviewOptions {
  /// Options for a preview of [url].
  const LinkPreviewOptions({
    required this.url,
    this.media = LinkPreviewMedia.auto,
    this.removed = false,
  });

  /// The URL the preview shows, chosen among the text's links.
  final Uri url;

  /// How large the preview's media is drawn.
  final LinkPreviewMedia media;

  /// Whether the message shows no preview: the sender removed it, or the
  /// chat does not allow previews. [url] is kept, so restoring the preview
  /// in a draft does not lose the choice.
  final bool removed;

  /// These options with the fields given replaced.
  LinkPreviewOptions copyWith({
    Uri? url,
    LinkPreviewMedia? media,
    bool? removed,
  }) => LinkPreviewOptions(
    url: url ?? this.url,
    media: media ?? this.media,
    removed: removed ?? this.removed,
  );

  @override
  bool operator ==(Object other) =>
      other is LinkPreviewOptions &&
      other.url == url &&
      other.media == media &&
      other.removed == removed;

  @override
  int get hashCode => Object.hash(url, media, removed);

  @override
  String toString() =>
      'LinkPreviewOptions(${url.host}, ${media.value}, removed: $removed)';
}
