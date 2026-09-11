import 'package:chat_md_selection/src/chat_md_selection_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_md/flutter_md.dart';

/// Paints a registered markdown body; mounts a selection surface when
/// [ChatMdSelectionController.exposesSelectionSurface] is true for
/// [messageId].
///
/// Mobile: selected bodies mount for span-yield hit-testing. Desktop/web:
/// registered bodies mount while message membership is empty so direct entry
/// can hit-test. Character-range gestures stay gated by
/// [ChatMdSelectionController.armsMarkdownGestures] /
/// [ChatMdSelectionScope.enabled] — a mounted surface alone does not enable
/// them. Resolves the model via [ChatMdSelectionController.bodyOf]. Call
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
        final mountSurface = controller.exposesSelectionSurface(messageId);
        return switch (model) {
          null => const SizedBox.shrink(),
          final md => MarkdownWidget(
            markdown: md,
            documentId: mountSurface ? messageId : null,
            controller: mountSurface ? controller.markdownSelection : null,
          ),
        };
      },
    );
  }
}
