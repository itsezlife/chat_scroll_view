import 'package:content_model/content_model.dart';
import 'package:flutter/foundation.dart';

/// The draft's link preview part, as the draft options overlay edits it:
/// the message's [options] for its preview and its [invertMedia] flag.
///
/// The overlay takes the host's current value and reports edited ones; the
/// host writes the draft.
@immutable
final class DraftLinkPart {
  /// A link part of [options], the card below the text unless [invertMedia].
  const DraftLinkPart({required this.options, this.invertMedia = false});

  /// Which URL previews, how large, or none at all.
  final LinkPreviewOptions options;

  /// Whether the card sits above the text: the message-level flag, not an
  /// option of the preview.
  final bool invertMedia;

  /// This part with the fields given replaced.
  DraftLinkPart copyWith({LinkPreviewOptions? options, bool? invertMedia}) =>
      DraftLinkPart(
        options: options ?? this.options,
        invertMedia: invertMedia ?? this.invertMedia,
      );

  @override
  bool operator ==(Object other) =>
      other is DraftLinkPart &&
      other.options == options &&
      other.invertMedia == invertMedia;

  @override
  int get hashCode => Object.hash(options, invertMedia);

  @override
  String toString() => 'DraftLinkPart($options, invertMedia: $invertMedia)';
}

/// Which field of the link part an edit changed, as the events name it.
enum DraftOptionsField {
  /// Above or below the text ([DraftLinkPart.invertMedia]).
  position,

  /// Larger or smaller media ([LinkPreviewOptions.media]).
  size,

  /// No preview ([LinkPreviewOptions.removed]).
  remove,

  /// Another link of the text ([LinkPreviewOptions.url]).
  link,
}
