import 'package:chat_md_selection/src/chat_md_selection_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_md/flutter_md.dart';

/// Exposes [ChatMdSelectionController.markdownSelection] and enables markdown
/// selection gestures only while text selection is active.
///
/// Mount above [ChatMdBody] rows. Selected bodies may mount surfaces for span
/// yield hit-testing while [enabled] stays false until
/// [ChatMdSelectionController.enterTextSelection]. Rebuilds when the
/// controller notifies.
class ChatMdSelectionScope extends StatelessWidget {
  /// Creates a scope driven by [controller].
  const ChatMdSelectionScope({
    required this.controller,
    required this.child,
    this.focusNode,
    this.selectionColor,
    this.contextMenuBuilder =
        MarkdownSelectionScope.defaultContextMenuBuilder,
    this.magnifierConfiguration,
    this.selectionControls,
    this.onSelectionChanged,
    super.key,
  });

  /// Text-selection controller (arming + markdown SoT).
  final ChatMdSelectionController controller;

  /// Subtree containing markdown bodies.
  final Widget child;

  /// Focus node forwarded to [MarkdownSelectionScope]; null creates one.
  final FocusNode? focusNode;

  /// Selection highlight color; null uses ambient theme defaults.
  final Color? selectionColor;

  /// Toolbar builder. Defaults to adaptive Copy / Select all.
  final MarkdownSelectionContextMenuBuilder? contextMenuBuilder;

  /// Magnifier configuration for touch handle drags.
  final TextMagnifierConfiguration? magnifierConfiguration;

  /// Handle controls; null uses platform defaults.
  final TextSelectionControls? selectionControls;

  /// Called when the markdown selection changes.
  final ValueChanged<MarkdownSelection?>? onSelectionChanged;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return MarkdownSelectionScope(
          controller: controller.markdownSelection,
          enabled: controller.isTextSelectionActive,
          focusNode: focusNode,
          selectionColor: selectionColor,
          contextMenuBuilder: contextMenuBuilder,
          magnifierConfiguration: magnifierConfiguration,
          selectionControls: selectionControls,
          onSelectionChanged: onSelectionChanged,
          autoscroll: MarkdownSelectionAutoscrollConfig.disabled,
          child: child,
        );
      },
    );
  }
}
