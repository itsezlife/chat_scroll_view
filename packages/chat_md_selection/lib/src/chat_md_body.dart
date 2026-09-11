import 'package:chat_md_selection/src/chat_md_selection_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_md/flutter_md.dart';

/// Paints a registered markdown body; exposes `documentId` only while
/// [messageId] is the armed text-selection subject.
///
/// Resolves the model via [ChatMdSelectionController.bodyOf]. Call
/// [ChatMdSelectionController.putBody] before paint; a missing body yields
/// [SizedBox.shrink].
class ChatMdBody extends StatelessWidget {
  /// Creates a body for [messageId] driven by [controller].
  const ChatMdBody({
    required this.controller,
    required this.messageId,
    super.key,
  });

  /// Text-selection controller (body registry + arming).
  final ChatMdSelectionController controller;

  /// Message ID whose registered markdown model to paint.
  final int messageId;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final model = controller.bodyOf(messageId);
        final armed = controller.isDocumentArmed(messageId);
        return switch (model) {
          null => const SizedBox.shrink(),
          final md => MarkdownWidget(
            markdown: md,
            documentId: armed ? messageId : null,
            controller: armed ? controller.markdownSelection : null,
          ),
        };
      },
    );
  }
}
