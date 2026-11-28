import 'package:chrome_foundation/chrome_foundation.dart' show MediaStrings;
import 'package:content_model/content_model.dart' show MediaItemKind;
import 'package:meta/meta.dart';

/// What a screen reader hears for a message's media, composed from the
/// host's [MediaStrings].
///
/// Each item is one node, labelled by [label]: its kind, then its duration
/// (a video, an animation that knows one) or its size (a file, or any item
/// not downloaded yet), then its progress while it loads. A card's node is
/// [cardLabel].
@internal
extension MediaSemanticsLabels on MediaStrings {
  /// [kind] as a screen reader names it: photo, video, animation, and every
  /// other kind a file.
  String kindOf(MediaItemKind kind) => switch (kind) {
    MediaItemKind.photo => photoKind,
    MediaItemKind.video => videoKind,
    MediaItemKind.animation => animationKind,
    _ => fileKind,
  };

  /// The node's label: the kind, then [duration] or [size] where the item
  /// has one, then the progress while [loading].
  String label({
    required MediaItemKind kind,
    Duration? duration,
    int? size,
    bool loading = false,
    double? fraction,
  }) => [
    kindOf(kind),
    if (duration != null) this.duration(duration),
    if (size != null) this.size(size),
    if (loading) downloadProgress(fraction),
  ].join(', ');

  /// A card's label: [pagePreview], then the [title] and the [text] where
  /// the page has them.
  String cardLabel({String? title, String? text}) =>
      [pagePreview, ?title, ?text].join(', ');
}
