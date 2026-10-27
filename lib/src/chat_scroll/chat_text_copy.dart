import 'package:chat_scroll_view/src/chat_scroll/chat_selection_interaction.dart';
import 'package:flutter_md/flutter_md.dart' show MarkdownSelectedContent;
import 'package:meta/meta.dart';

/// What the viewport copies, handed to a host that writes the clipboard
/// itself (`ChatSelectionController.copyWriter`).
///
/// [plainText] is what the viewport would put on the platform clipboard on
/// its own. A host that keeps formatting on the clipboard builds its rich
/// form from [content] (the selected blocks with their spans and the
/// selected range of each) or, for a code tap, from [codeLanguage].
@immutable
final class ChatTextCopy {
  /// Creates a copy of [plainText] from [origin].
  const ChatTextCopy({required this.plainText, required this.origin, this.messageId, this.content, this.codeLanguage});

  /// The copied text as plain text.
  final String plainText;

  /// What was copied: a text selection or a code tap.
  final ChatCopyOrigin origin;

  /// The message copied from: the text selection's subject, or the message
  /// holding the tapped code.
  final int? messageId;

  /// The selected markdown content of a text selection; null for a code tap.
  final MarkdownSelectedContent? content;

  /// The tapped code block's language, when it declares one.
  final String? codeLanguage;
}

/// Writes a [ChatTextCopy] to the clipboard; completes when it is written.
typedef ChatTextCopyWriter = Future<void> Function(ChatTextCopy copy);
