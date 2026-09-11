import 'package:chat_md_selection/src/chat_md_selection_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_md/flutter_md.dart';

/// Mounts [MarkdownSelectionScope] for [controller], enabled when
/// [ChatMdSelectionController.armsMarkdownGestures] is true.
///
/// Mobile: inert until text selection is active. Desktop/web: armed for
/// direct drag / double-click / keyboard entry while message membership is
/// empty. Place above [ChatMdBody] rows. Default toolbar Copy calls
/// [ChatMdSelectionController.copyTextSelection]; hosts that pass
/// [contextMenuBuilder] own Copy handling.
class ChatMdSelectionScope extends StatelessWidget {
  /// Creates a scope driven by [controller].
  const ChatMdSelectionScope({
    required this.controller,
    required this.child,
    this.focusNode,
    this.selectionColor,
    this.contextMenuBuilder,
    this.magnifierConfiguration,
    this.selectionControls,
    this.onSelectionChanged,
    super.key,
  });

  /// Text-selection controller.
  final ChatMdSelectionController controller;

  /// Subtree containing markdown bodies.
  final Widget child;

  /// Focus node for [MarkdownSelectionScope]; null creates one.
  final FocusNode? focusNode;

  /// Selection highlight color; null uses ambient theme defaults.
  final Color? selectionColor;

  /// Toolbar builder; null uses [defaultContextMenuBuilder].
  final MarkdownSelectionContextMenuBuilder? contextMenuBuilder;

  /// Magnifier configuration for touch handle drags.
  final TextMagnifierConfiguration? magnifierConfiguration;

  /// Handle controls; null uses platform defaults.
  final TextSelectionControls? selectionControls;

  /// Called when the markdown selection changes.
  final ValueChanged<MarkdownSelection?>? onSelectionChanged;

  /// Default toolbar: Copy → [ChatMdSelectionController.copyTextSelection].
  static Widget defaultContextMenuBuilder(
    BuildContext context,
    MarkdownSelectionScopeState state,
    ChatMdSelectionController controller,
  ) {
    final items = <ContextMenuButtonItem>[
      for (final item in state.contextMenuButtonItems)
        switch (item.type) {
          ContextMenuButtonType.copy => ContextMenuButtonItem(
            type: ContextMenuButtonType.copy,
            onPressed: () {
              controller.copyTextSelection();
            },
          ),
          _ => item,
        },
    ];
    return AdaptiveTextSelectionToolbar.buttonItems(
      buttonItems: items,
      anchors: state.contextMenuAnchors,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return MarkdownSelectionScope(
          controller: controller.markdownSelection,
          enabled: controller.armsMarkdownGestures,
          focusNode: focusNode,
          selectionColor: selectionColor,
          contextMenuBuilder:
              contextMenuBuilder ??
              (context, state) =>
                  defaultContextMenuBuilder(context, state, controller),
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
