import 'package:chat_composer/src/draft_options/draft_link_part.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/widgets.dart' hide RichText;

/// What the draft options overlay asks of its host.
///
/// The composer does not own drafts: the overlay takes the current value
/// and reports edits here, and the host writes the draft. When an edit
/// arrives depends on the policy's apply mode.
abstract interface class DraftOptionsHost {
  /// The link part is now [part]: the host writes it into the draft.
  void linkPartEdited(DraftLinkPart part);
}

/// The draft as the live preview draws it: its [text], its link [part] and
/// the [page] the link resolved to so far.
@immutable
final class DraftOptionsPreview {
  /// A preview of a draft.
  const DraftOptionsPreview({
    required this.text,
    required this.part,
    required this.page,
  });

  /// The draft's text.
  final RichText text;

  /// The link part as the overlay shows it now: the host's value under live
  /// apply, the overlay's copy under commit on save.
  final DraftLinkPart part;

  /// Where the link's page stands; pending draws no card.
  final LinkPreviewState page;
}

/// Builds the live preview of the draft as the real message bubble, the way
/// the chat draws it (its media policy, its wallpaper under the bubble).
///
/// The overlay knows no message media and no wallpaper: the host's builder
/// draws both. The preview's text is not selectable.
typedef DraftOptionsBubbleBuilder =
    Widget Function(BuildContext context, DraftOptionsPreview preview);
