import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:panel_catalog/panel_catalog.dart';

/// Moves roving focus one step across the catalogue.
class CatalogMoveFocusIntent extends Intent {
  /// An intent to move focus by [move].
  const CatalogMoveFocusIntent(this.move);

  /// The step; the arrows are physical, see [CatalogFocusMove].
  final CatalogFocusMove move;
}

/// The key bindings of the catalogue's roving focus: the arrows move by cell,
/// Home and End go to the ends, and Enter, numpad Enter and Space activate the
/// focused cell as a tap would.
///
/// Mounted above the viewport by [CatalogPage]. The bindings are scoped to the
/// subtree that holds focus, so a text field elsewhere keeps its own arrows.
/// The controller owns the focus itself (it lives in the viewport); this
/// widget only turns keys into the controller's `moveFocus` and
/// `activateFocusedLeaf`, enters the grid when the widget takes focus, and
/// ends roving focus when it loses it.
class CatalogKeyboardFocus extends StatefulWidget {
  /// Binds the keys for [controller] around [child].
  const CatalogKeyboardFocus({
    required this.controller,
    required this.child,
    super.key,
  });

  /// The catalogue controller the keys drive.
  final PanelCatalogController controller;

  /// The viewport and whatever surrounds it.
  final Widget child;

  /// The keys and what they move.
  static const Map<ShortcutActivator, Intent> shortcuts =
      <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.arrowRight): CatalogMoveFocusIntent(
          CatalogFocusMove.right,
        ),
        SingleActivator(LogicalKeyboardKey.arrowLeft): CatalogMoveFocusIntent(
          CatalogFocusMove.left,
        ),
        SingleActivator(LogicalKeyboardKey.arrowDown): CatalogMoveFocusIntent(
          CatalogFocusMove.down,
        ),
        SingleActivator(LogicalKeyboardKey.arrowUp): CatalogMoveFocusIntent(
          CatalogFocusMove.up,
        ),
        SingleActivator(LogicalKeyboardKey.home): CatalogMoveFocusIntent(
          CatalogFocusMove.first,
        ),
        SingleActivator(LogicalKeyboardKey.end): CatalogMoveFocusIntent(
          CatalogFocusMove.last,
        ),
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
      };

  @override
  State<CatalogKeyboardFocus> createState() => _CatalogKeyboardFocusState();
}

class _CatalogKeyboardFocusState extends State<CatalogKeyboardFocus> {
  late final Map<Type, Action<Intent>> _actions = <Type, Action<Intent>>{
    CatalogMoveFocusIntent: CallbackAction<CatalogMoveFocusIntent>(
      onInvoke: (intent) => widget.controller.moveFocus(intent.move),
    ),
    ActivateIntent: CallbackAction<ActivateIntent>(
      onInvoke: (_) => widget.controller.activateFocusedLeaf(),
    ),
  };

  void _onFocusChange(bool hasFocus) {
    final controller = widget.controller;
    if (!hasFocus) {
      controller.clearFocus();
    } else if (controller.focusedLeaf == null) {
      // Entering by Tab shows where focus is; with no focus a step lands on the
      // first cell in view.
      controller.moveFocus(CatalogFocusMove.next);
    }
  }

  @override
  Widget build(BuildContext context) => Shortcuts(
    shortcuts: CatalogKeyboardFocus.shortcuts,
    child: Actions(
      actions: _actions,
      child: Focus(onFocusChange: _onFocusChange, child: widget.child),
    ),
  );
}
