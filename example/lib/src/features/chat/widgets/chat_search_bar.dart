import 'package:chat_scroll_view_example/src/features/chat/controller/chat_search_controller.dart';
import 'package:chat_scroll_view_example/src/features/chat/controller/chat_search_state.dart';
import 'package:control/control.dart';
import 'package:flutter/material.dart';

/// Top search field driven by [ChatSearchController] under [ControllerScope].
class ChatSearchBar extends StatefulWidget {
  /// Creates the demo search field overlay.
  const ChatSearchBar({super.key});

  @override
  State<ChatSearchBar> createState() => _ChatSearchBarState();
}

class _ChatSearchBarState extends State<ChatSearchBar> {
  final _field = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _field.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final controller = context.controllerOf<ChatSearchController>();

    return Material(
      elevation: 2,
      color: colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(24),
      child: ValueListenableBuilder(
        valueListenable: controller.select(
          (s) => s.maybeMap(searching: (_) => true, orElse: () => false),
        ),
        builder: (context, isSearching, _) => TextField(
          controller: _field,
          focusNode: _focus,
          textInputAction: TextInputAction.search,
          onSubmitted: controller.submit,
          decoration: InputDecoration(
            hintText: 'Search all messages',
            isDense: true,
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
            suffixIcon: isSearching
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    tooltip: 'Find',
                    onPressed: () => controller.submit(_field.text),
                    icon: const Icon(Icons.arrow_forward, size: 20),
                  ),
          ),
        ),
      ),
    );
  }
}

/// Toolbar toggle that opens / closes global search.
class ChatSearchToggleButton extends StatelessWidget {
  /// Creates the search open/close icon button.
  const ChatSearchToggleButton({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.controllerOf<ChatSearchController>(); 
    return ValueListenableBuilder(
      valueListenable: controller.select(
        (s) => s.maybeMap(closed: (_) => false, orElse: () => true),
      ),
      builder: (context, isOpen, _) => IconButton.filledTonal(
        tooltip: isOpen ? 'Close search' : 'Search',
        onPressed: () {
          if (isOpen) {
            controller.close();
          } else {
            controller.open();
          }
        },
        icon: Icon(isOpen ? Icons.close : Icons.search, size: 20),
      ),
    );
  }
}
