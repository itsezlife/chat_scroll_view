import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view_example/src/common/widgets/value_observable_builder.dart';
import 'package:chat_scroll_view_example/src/features/chat/input/chat_input_set.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/chat_composer.dart';
import 'package:flutter/widgets.dart';
import 'package:panel_presentation/panel_presentation.dart';

/// The chat's bottom chrome: the composer and, under it, the room the panel
/// takes.
///
/// Where the panel replaces the soft keyboard (a mobile policy) the room is a
/// box as tall as the presentation's occupancy, which holds the soft keyboard
/// while it is up and the panel while it is, and the panel's view fills it.
/// Elsewhere the panel is a popup or a dock the screen draws over the chat,
/// the occupancy at the bottom is zero, and this widget only wraps the
/// composer in the actions Escape and the toggle shortcut need.
class ChatBottomChrome extends StatefulWidget {
  /// The bottom chrome of [input].
  const ChatBottomChrome({
    required this.input,
    required this.selection,
    required this.islandKey,
    this.anchorSpace,
    this.onAttachPressed,
    this.onVoicePressed,
    super.key,
  });

  /// The chat's input set.
  final ChatInputSet input;

  /// While a selection is active the composer is hidden.
  final ChatSelectionController selection;

  /// Key of the composer's glass island.
  final GlobalKey islandKey;

  /// The box the popup's anchor is reported in; null where there is no popup.
  final GlobalKey? anchorSpace;

  /// Attach button.
  final VoidCallback? onAttachPressed;

  /// The voice button.
  final VoidCallback? onVoicePressed;

  /// Whether the panel replaces the soft keyboard under [input]'s policy.
  static bool replacesKeyboard(ChatInputSet input) =>
      input.presentation.policy is PanelPresentationPolicy$Mobile;

  @override
  State<ChatBottomChrome> createState() => _ChatBottomChromeState();
}

class _ChatBottomChromeState extends State<ChatBottomChrome> {
  // Built once: the strategy keeps the shell mounted, and a frame of the
  // slot's motion rebuilds only the box around it.
  late final Widget _panelView = RepaintBoundary(
    child: PanelPresentationView(controller: widget.input.presentation),
  );

  @override
  Widget build(BuildContext context) {
    final input = widget.input;
    final replacesKeyboard = ChatBottomChrome.replacesKeyboard(input);
    final composer = ChatComposer(
      input: input,
      selection: widget.selection,
      islandKey: widget.islandKey,
      anchorSpace: replacesKeyboard ? null : widget.anchorSpace,
      onAttachPressed: widget.onAttachPressed,
      onVoicePressed: widget.onVoicePressed,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (replacesKeyboard)
          composer
        else
          Shortcuts(
            shortcuts: AnchoredPopupShortcuts.standard,
            child: AnchoredPopupActions(
              controller: input.presentation,
              child: composer,
            ),
          ),
        if (replacesKeyboard)
          ValueObservableBuilder<PanelOccupancy>(
            observable: input.presentation.occupancy,
            builder: (context, occupancy) =>
                SizedBox(height: occupancy.bottom, child: _panelView),
          ),
      ],
    );
  }
}
