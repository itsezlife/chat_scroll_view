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
/// On a desktop the catalogue under the mouse has the keys: while the mouse
/// is over it, and after a mouse press on it, it holds the focus without a
/// focused cell, so the keys scroll it and not the chat beside it. A text
/// field that holds the focus (the composer the user types in while
/// picking) keeps it and its keys. Focus the hover took goes back to where
/// it was when the mouse leaves, unless a press or a cell kept it. The controller owns the roving focus itself (it
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

  // The focus requested is the mouse's: no cell is focused for it. The
  // focus change arrives after the request, which it consumes.
  var _pressing = false;

  // Where the focus the hover took was, to go back to when the mouse leaves;
  // null when a press took it, or nothing had it.
  FocusNode? _returnTo;

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  void _onPointerDown(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.mouse) return;
    // A press keeps the keys here once the mouse leaves.
    _returnTo = null;
    _takeKeys();
  }

  void _onEnter(PointerEnterEvent event) {
    if (event.kind != PointerDeviceKind.mouse) return;
    final primary = FocusManager.instance.primaryFocus;
    if (_takeKeys()) {
      _returnTo = primary is FocusScopeNode ? null : primary;
    }
  }

  void _onExit(PointerExitEvent event) {
    final back = _returnTo;
    _returnTo = null;
    // A cell focused meanwhile (by Tab) keeps the keys here.
    if (back == null || widget.controller.focusedLeaf != null) return;
    if (!_node.hasFocus && !_pressing) return;
    if (back.context != null && back.canRequestFocus) back.requestFocus();
  }

  // Takes the focus for the mouse, unless it is here already or a text
  // field holds it; returns whether it asked for it.
  bool _takeKeys() {
    if (_node.hasFocus) return false;
    final primary = FocusManager.instance.primaryFocus;
    if (_typesText(primary)) return false;
    _pressing = true;
    _node.requestFocus();
    return true;
  }

  // Whether [node] is a text field's: its keys are the text's.
  static bool _typesText(FocusNode? node) {
    final context = node?.context;
    if (context == null) return false;
    if (context case StatefulElement(
      :final state,
    ) when state is TextInputClient) {
      return true;
    }
    var found = false;
    context.visitAncestorElements((element) {
      if (element case StatefulElement(
        :final state,
      ) when state is TextInputClient) {
        found = true;
        return false;
      }
      return true;
    });
    return found;
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
            child: MouseRegion(
              opaque: false,
              onEnter: _onEnter,
              onExit: _onExit,
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: _onPointerDown,
                child: widget.child,
              ),
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
