import 'package:chat_composer/src/draft_options/draft_link_part.dart';
import 'package:chrome_foundation/chrome_foundation.dart'
    show ChromeMenuRowTiming, MotionSpec;
import 'package:content_model/content_model.dart';
import 'package:flutter/widgets.dart' hide RichText;
import 'package:listen/listen.dart' as listen;

/// What the draft options overlay asks of its host.
///
/// The composer does not own drafts: the overlay takes the current value
/// and reports edits here, and the host writes the draft. When an edit
/// arrives depends on the policy's apply mode.
abstract interface class DraftOptionsHost {
  /// The link part is now [part]: the host writes it into the draft.
  ///
  /// The user's edits, the remove row's included: that row has applied the
  /// link preview dismissal (as the strip's cross does) before the edit
  /// arrives, so the host follows it.
  void linkPartEdited(DraftLinkPart part);

  /// Link previews became denied while the options were up; they have
  /// closed, and the draft's link part is [part], its preview removed. The
  /// host records it in the draft. Nothing applied a dismissal: the denial
  /// is the chat's, not the user's choice.
  void previewDenied(DraftLinkPart part);

  /// The user chose [url], a link of the draft's text, as the one to
  /// preview: the host re-asks its resolver for that link alone and returns
  /// the lookup, which the overlay follows from pending to loaded or none.
  ///
  /// The choice itself reaches the draft as an edit of the url, by the
  /// apply mode like any other ([linkPartEdited]); under commit on save a
  /// cancel discards it, though the lookup already ran. A cache of pages
  /// already resolved is the host's or its resolver's: the overlay asks
  /// again on every choice.
  listen.ValueListenable<LinkPreviewState> chooseLink(Uri url);
}

/// A tap on a link in the live preview: its [url] as the text spells it and
/// its [contourPath], the outline of the link's text in the bubble's
/// coordinates, which the overlay draws as the chosen link's highlight.
typedef DraftLinkTap = void Function(String url, Path contourPath);

/// The draft as the live preview draws it: its [text], its link [part] and
/// the [page] the link resolved to so far.
@immutable
final class DraftOptionsPreview {
  /// A preview of a draft.
  const DraftOptionsPreview({
    required this.text,
    required this.part,
    required this.page,
    required this.onLinkTap,
    this.selectable = false,
    this.linkCursor = MouseCursor.defer,
    this.change = ChromeMenuRowTiming.labelInstant,
  });

  /// The draft's text.
  final RichText text;

  /// The link part as the overlay shows it now: the host's value under live
  /// apply, the overlay's copy under commit on save.
  final DraftLinkPart part;

  /// Where the link's page stands; pending draws no card.
  final LinkPreviewState page;

  /// What the bubble calls when a link of its text is tapped, with the
  /// link's contour from the bubble's inline hit; the overlay decides
  /// whether the tap chooses that link.
  final DraftLinkTap onLinkTap;

  /// Whether the message's and the card's text may be selected: false in
  /// the preview, where a press on text is a link choice or nothing.
  final bool selectable;

  /// The cursor the bubble sets over a link of its text, where a mouse
  /// points (the click cursor in a desktop box); [MouseCursor.defer] leaves
  /// the bubble's own.
  final MouseCursor linkCursor;

  /// How the bubble's layout moves from the previous preview to this one,
  /// the presentation's option change: at once for a zero duration. The
  /// builder hands it to its media layout's transition.
  final MotionSpec change;
}

/// Builds the live preview of the draft as the real message bubble, the way
/// the chat draws it (its media policy, its wallpaper under the bubble).
///
/// The overlay knows no message media and no wallpaper: the host's builder
/// draws both. The preview's text is not selectable
/// ([DraftOptionsPreview.selectable]); a link tap goes to
/// [DraftOptionsPreview.onLinkTap]. The bubble's change between two previews
/// is the builder's: the host's media layout interpolates it with the
/// platform's transition.
typedef DraftOptionsBubbleBuilder =
    Widget Function(BuildContext context, DraftOptionsPreview preview);
