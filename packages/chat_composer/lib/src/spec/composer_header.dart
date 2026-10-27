import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/widgets.dart';

/// What sits above the field: a reply, an edit, a forward, a link preview or
/// a host-built suggestion.
///
/// The header is one of the composer's three slots. It is data the host puts
/// in a [ComposerSpec]; the composer reveals and hides the strip with the
/// `headerReveal` motion role and draws the stock variants. Titles that are
/// language ("Reply to Ada", "Editing message") come from
/// `ChromeStrings.composer`, not from the host's pre-formatted text.
///
/// A host that can have several headers at once (replying while a link
/// preview is open) passes the candidates to [prioritised].
sealed class ComposerHeader {
  const ComposerHeader({this.onDismiss});

  /// A reply to the person called [name]; [preview] is a short quote of the
  /// message.
  const factory ComposerHeader.reply({
    required String name,
    required String preview,
    VoidCallback? onDismiss,
  }) = ComposerHeader$Reply;

  /// Editing a message whose current text is summarised by [preview].
  const factory ComposerHeader.edit({
    required String preview,
    VoidCallback? onDismiss,
  }) = ComposerHeader$Edit;

  /// Forwarding messages: [title] says what, [preview] summarises them.
  const factory ComposerHeader.forward({
    required String title,
    required String preview,
    ChromeIconId icon,
    VoidCallback? onDismiss,
  }) = ComposerHeader$Forward;

  /// A preview of the link in the field: [title] is the page, [preview] its
  /// address or description.
  const factory ComposerHeader.linkPreview({
    required String title,
    required String preview,
    ChromeIconId icon,
    VoidCallback? onDismiss,
  }) = ComposerHeader$LinkPreview;

  /// Host-built content in the strip, such as a suggestion bar. The builder's
  /// widget gets the strip's full width and [ComposerMetrics.headerHeight].
  const factory ComposerHeader.suggestion({
    required WidgetBuilder builder,
    VoidCallback? onDismiss,
  }) = ComposerHeader$Suggestion;

  /// A chip for something attached to the message, such as the screen the
  /// user is looking at: [title] says what, [removeLabel] names the trailing
  /// action (both in the host's language) and [onRemove] is the host's answer
  /// to a tap on it, which clears the header from the next spec.
  ///
  /// There is no [onDismiss] control and no Escape dismissal: the labelled
  /// remove action is the only way out. It has the lowest priority, so a
  /// reply, edit or any other header takes the single strip over it.
  const factory ComposerHeader.attachment({
    required String title,
    required String removeLabel,
    required VoidCallback onRemove,
    ChromeIconId icon,
  }) = ComposerHeader$Attachment;

  /// Called by the strip's dismiss control. Null shows no control.
  final VoidCallback? onDismiss;

  /// How strongly this header claims the strip when several compete; higher
  /// wins. Edit, then reply, forward, link preview, suggestion and attachment.
  int get priority;

  /// The candidate with the highest [priority], the first of equals, or null
  /// when there is none. Null candidates are skipped, so a host can pass
  /// `[edit, reply, preview]` with absent ones as null.
  static ComposerHeader? prioritised(Iterable<ComposerHeader?> candidates) {
    ComposerHeader? best;
    for (final candidate in candidates) {
      if (candidate == null) continue;
      if (best == null || candidate.priority > best.priority) best = candidate;
    }
    return best;
  }
}

/// A reply; see [ComposerHeader.reply].
final class ComposerHeader$Reply extends ComposerHeader {
  /// Creates a reply header.
  const ComposerHeader$Reply({
    required this.name,
    required this.preview,
    super.onDismiss,
  });

  /// Display name of the person replied to.
  final String name;

  /// Short quote of the replied-to message.
  final String preview;

  @override
  int get priority => 4;
}

/// An edit; see [ComposerHeader.edit].
final class ComposerHeader$Edit extends ComposerHeader {
  /// Creates an edit header.
  const ComposerHeader$Edit({required this.preview, super.onDismiss});

  /// Summary of the message being edited.
  final String preview;

  @override
  int get priority => 5;
}

/// A forward; see [ComposerHeader.forward].
final class ComposerHeader$Forward extends ComposerHeader {
  /// Creates a forward header.
  const ComposerHeader$Forward({
    required this.title,
    required this.preview,
    this.icon = const ChromeIconId('forward'),
    super.onDismiss,
  });

  /// What is being forwarded, already in the host's language.
  final String title;

  /// Summary of the forwarded messages.
  final String preview;

  /// Glyph of the strip. The stock registry has none for `forward`; a host
  /// registers a painter (unknown ids fall back to a neutral glyph).
  final ChromeIconId icon;

  @override
  int get priority => 3;
}

/// A link preview; see [ComposerHeader.linkPreview].
final class ComposerHeader$LinkPreview extends ComposerHeader {
  /// Creates a link preview header.
  const ComposerHeader$LinkPreview({
    required this.title,
    required this.preview,
    this.icon = const ChromeIconId('link'),
    super.onDismiss,
  });

  /// Title of the linked page, in the host's language.
  final String title;

  /// Address or description of the link.
  final String preview;

  /// Glyph of the strip. The stock registry has none for `link`; a host
  /// registers a painter.
  final ChromeIconId icon;

  @override
  int get priority => 2;
}

/// An attachment chip; see [ComposerHeader.attachment].
final class ComposerHeader$Attachment extends ComposerHeader {
  /// Creates an attachment header.
  const ComposerHeader$Attachment({
    required this.title,
    required this.removeLabel,
    required this.onRemove,
    this.icon = const ChromeIconId('attachment'),
  });

  /// What is attached, in the host's language.
  final String title;

  /// Label of the remove action, in the host's language.
  final String removeLabel;

  /// Called when the remove action is tapped.
  final VoidCallback onRemove;

  /// Glyph of the chip. The stock registry may have none for `attachment`; a
  /// host registers a painter.
  final ChromeIconId icon;

  @override
  int get priority => 0;
}

/// A host-built strip; see [ComposerHeader.suggestion].
final class ComposerHeader$Suggestion extends ComposerHeader {
  /// Creates a suggestion header.
  const ComposerHeader$Suggestion({required this.builder, super.onDismiss});

  /// Builds the strip's content.
  final WidgetBuilder builder;

  @override
  int get priority => 1;
}
