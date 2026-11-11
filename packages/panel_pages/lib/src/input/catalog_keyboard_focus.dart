import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:panel_catalog/panel_catalog.dart';
import 'package:viewport_scroll/viewport_scroll.dart';

/// Moves roving focus one step across the catalogue.
class CatalogMoveFocusIntent extends Intent {
  /// An intent to move focus by [move].
  const CatalogMoveFocusIntent(this.move);

  /// The step; the arrows are physical, see [CatalogFocusMove].
  final CatalogFocusMove move;
}

/// The key bindings of the catalogue: its roving focus and the chat's scroll
/// keys ([ViewportScrollKeys]).
///
/// With a cell focused (roving focus, entered by Tab) the arrows move by
/// cell, Home and End go to the first and last cell, and Enter, numpad Enter
/// and Space activate the focused cell as a tap would. With none, the keys
/// scroll as the chat's do: the up and down arrows a line, Home and End to
/// the start and the end. The page keys always scroll.
///
/// Mounted above the viewport by [CatalogPage]. The bindings are scoped to the
/// subtree that holds focus, so a text field elsewhere keeps its own arrows.
/// A mouse press on the catalogue gives it the keys without focusing a cell,
/// unless a node outside it holds the focus (a composer the user types in
/// while picking keeps it). The controller owns the roving focus itself (it
/// lives in the viewport); this widget only turns keys into the controller's
/// `moveFocus`, `activateFocusedLeaf` and scroll calls, enters the grid when
/// the focus arrives by traversal, and ends roving focus when it leaves.
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
    CatalogMoveFocusIntent: _MoveFocusAction(this),
    ActivateIntent: CallbackAction<ActivateIntent>(
      onInvoke: (_) => widget.controller.activateFocusedLeaf(),
    ),
  };

  final FocusNode _node = FocusNode(debugLabel: 'CatalogKeyboardFocus');

  // The focus requested is a mouse press's: no cell is focused for it. The
  // focus change arrives after the request, which it consumes.
  var _pressing = false;

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  void _onPointerDown(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.mouse || _node.hasFocus) return;
    // A node beside the catalogue that holds the focus keeps it; one above
    // it (the route's scope) holds it for nobody.
    final primary = FocusManager.instance.primaryFocus;
    if (primary != null && !_node.ancestors.contains(primary)) return;
    _pressing = true;
    _node.requestFocus();
  }

  void _onFocusChange(bool hasFocus) {
    final controller = widget.controller;
    final pressed = _pressing;
    _pressing = false;
    if (!hasFocus) {
      controller.clearFocus();
    } else if (controller.focusedLeaf == null && !pressed) {
      // Entering by Tab shows where focus is; with no focus a step lands on the
      // first cell in view.
      controller.moveFocus(CatalogFocusMove.next);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return ViewportScrollKeys(
      onScrollBy: controller.scrollBy,
      onScrollToStart: () => controller.jumpTo(0),
      onScrollToEnd: () => controller.jumpTo(controller.maxScrollExtent),
      child: Shortcuts(
        shortcuts: CatalogKeyboardFocus.shortcuts,
        child: Actions(
          actions: _actions,
          child: Focus(
            focusNode: _node,
            onFocusChange: _onFocusChange,
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: _onPointerDown,
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

// Moves roving focus while a cell has it; with none the arrows and Home and
// End are left to the scroll keys above.
class _MoveFocusAction extends Action<CatalogMoveFocusIntent> {
  _MoveFocusAction(this._state);

  final _CatalogKeyboardFocusState _state;

  @override
  bool isEnabled(CatalogMoveFocusIntent intent) =>
      _state.widget.controller.focusedLeaf != null;

  @override
  Object? invoke(CatalogMoveFocusIntent intent) =>
      _state.widget.controller.moveFocus(intent.move);
}
