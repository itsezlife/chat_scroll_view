import 'package:meta/meta.dart';

/// Which of a link preview's media an id names.
///
/// A preview carries at most one of each: its [photo], and its [media] (a
/// video, an animation or a document the page embeds).
enum LinkPreviewMediaSlot {
  /// The page's photo.
  photo('photo'),

  /// The page's embedded media other than its photo.
  media('media');

  const LinkPreviewMediaSlot(this.value);

  /// The stable string written in a [MediaItemId]'s string form.
  final String value;

  static LinkPreviewMediaSlot? _fromValue(String value) {
    for (final slot in values) {
      if (slot.value == value) return slot;
    }
    return null;
  }
}

/// The identity of one media item in a chat.
///
/// Stable across edits, uploads and re-layouts, and unique in the chat, since
/// item state (a spoiler revealed, a transfer) is kept per chat. Equal by
/// value. Two variants that never equal each other:
///
/// - [MediaItemId.new]: an id the host issues, for an attachment.
/// - [MediaItemId.linkPreviewOf]: an id derived from a message and a
///   [LinkPreviewMediaSlot], for a link preview's media. The host issues
///   none for it, and no host id can collide with it.
///
/// ## String form
///
/// [toString] is a stable, lossless string that [parse] and [tryParse] read
/// back to an equal id. It is how the id crosses into code that names items
/// by an opaque string (a transfer's item, a diagnostics correlation id), so
/// distinct ids always give distinct strings:
///
/// | Variant | Form | Example |
/// | --- | --- | --- |
/// | host | `item:` and the host's id, verbatim | `item:a1` |
/// | link preview | `preview:`, the slot, `:`, and the message id, verbatim | `preview:photo:m1` |
///
/// The slot never holds `:`, so a message id that does still reads back.
@immutable
sealed class MediaItemId {
  /// The host-issued id [value], which must not be empty.
  const factory MediaItemId(String value) = MediaItemId$Host;

  /// The id of the media in [slot] of the link preview of the message
  /// [messageId], which must not be empty.
  ///
  /// The same message and slot give the same id on every call.
  const factory MediaItemId.linkPreviewOf(
    String messageId, {
    required LinkPreviewMediaSlot slot,
  }) = MediaItemId$LinkPreview;

  /// The id [source] is the string form of.
  ///
  /// Throws a [FormatException] carrying [source] when it is no id's string
  /// form; [tryParse] returns null instead.
  factory MediaItemId.parse(String source) =>
      tryParse(source) ??
      (throw FormatException('Not a MediaItemId string form.', source));

  const MediaItemId._();

  /// The id [source] is the string form of, or null when it is not one: no
  /// known prefix, an unknown slot, or an empty id.
  static MediaItemId? tryParse(String? source) {
    if (source == null) return null;
    final separator = source.indexOf(':');
    if (separator < 0) return null;
    final payload = source.substring(separator + 1);
    return switch (source.substring(0, separator)) {
      _hostTag when payload.isNotEmpty => MediaItemId(payload),
      _previewTag => _parsePreview(payload),
      _ => null,
    };
  }

  static MediaItemId? _parsePreview(String payload) {
    final separator = payload.indexOf(':');
    if (separator < 0) return null;
    final messageId = payload.substring(separator + 1);
    if (messageId.isEmpty) return null;
    return switch (LinkPreviewMediaSlot._fromValue(
      payload.substring(0, separator),
    )) {
      final slot? => MediaItemId.linkPreviewOf(messageId, slot: slot),
      null => null,
    };
  }

  static const String _hostTag = 'item';
  static const String _previewTag = 'preview';

  /// The string form; see [MediaItemId].
  @override
  String toString();
}

/// A host-issued [MediaItemId]; see [MediaItemId.new].
final class MediaItemId$Host extends MediaItemId {
  /// The id [value], which must not be empty.
  const MediaItemId$Host(this.value)
    : assert(value != '', 'A MediaItemId must not be empty.'),
      super._();

  /// The host's id.
  final String value;

  @override
  bool operator ==(Object other) =>
      other is MediaItemId$Host && other.value == value;

  @override
  int get hashCode => Object.hash(MediaItemId$Host, value);

  @override
  String toString() => '${MediaItemId._hostTag}:$value';
}

/// A link preview's [MediaItemId]; see [MediaItemId.linkPreviewOf].
final class MediaItemId$LinkPreview extends MediaItemId {
  /// The id of [slot] of [messageId]'s link preview.
  const MediaItemId$LinkPreview(this.messageId, {required this.slot})
    : assert(messageId != '', 'A message id must not be empty.'),
      super._();

  /// The message whose link preview carries the media.
  final String messageId;

  /// Which of the preview's media.
  final LinkPreviewMediaSlot slot;

  @override
  bool operator ==(Object other) =>
      other is MediaItemId$LinkPreview &&
      other.messageId == messageId &&
      other.slot == slot;

  @override
  int get hashCode => Object.hash(MediaItemId$LinkPreview, messageId, slot);

  @override
  String toString() => '${MediaItemId._previewTag}:${slot.value}:$messageId';
}
