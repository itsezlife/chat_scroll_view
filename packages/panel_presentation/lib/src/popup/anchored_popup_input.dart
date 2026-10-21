import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:panel_presentation/src/controller/panel_presentation_controller.dart';
import 'package:panel_shell/panel_shell.dart';

/// Asks the presentation to toggle the panel: the keyboard form of a click on
/// the composer's panel button.
///
/// No key is bound to it by default; a host picks its own and maps it in
/// [AnchoredPopupActions]' `Shortcuts`.
class AnchoredPopupToggleIntent extends Intent {
  /// An intent to toggle the panel.
  const AnchoredPopupToggleIntent();
}

/// The default key bindings of an anchored popup.
///
/// Escape is Flutter's [DismissIntent]; [AnchoredPopupActions] turns it into
/// a step back (search first, then the popup). The shell binds Escape and
/// the search shortcut inside itself; this map is for the part of the tree
/// outside it, such as the composer.
abstract final class AnchoredPopupShortcuts {
  /// Escape steps back.
  static const Map<ShortcutActivator, Intent> standard =
      <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
      };
}

/// The actions an anchored popup answers: [DismissIntent] steps back through
/// [PanelPresentationController.handleBack] (search closes first, the popup
/// second), [AnchoredPopupToggleIntent] toggles, and [PanelSearchIntent]
/// shows the panel if it is hidden and focuses the search field.
///
/// The popup mounts this above the shell, which is where the shell forwards
/// an Escape it has no search to close. A host that wants the same keys while
/// focus sits in the composer wraps the composer in it too, with
/// [AnchoredPopupShortcuts.standard] or its own map.
class AnchoredPopupActions extends StatelessWidget {
  /// Answers the popup's intents for [controller] below [child].
  const AnchoredPopupActions({
    required this.controller,
    required this.child,
    super.key,
  });

  /// The controller the intents act on.
  final PanelPresentationController controller;

  /// The subtree that sees the actions.
  final Widget child;

  @override
  Widget build(BuildContext context) => Actions(
    actions: <Type, Action<Intent>>{
      DismissIntent: _BackAction(controller),
      AnchoredPopupToggleIntent: CallbackAction<AnchoredPopupToggleIntent>(
        onInvoke: (_) {
          controller.toggle();
          return null;
        },
      ),
      PanelSearchIntent: CallbackAction<PanelSearchIntent>(
        onInvoke: (_) {
          if (!controller.state.value.isVisible) controller.show();
          controller.shell.openSearch();
          return null;
        },
      ),
    },
    child: child,
  );
}

class _BackAction extends Action<DismissIntent> {
  _BackAction(this._controller);

  final PanelPresentationController _controller;

  @override
  bool isEnabled(DismissIntent intent) => _controller.state.value.isVisible;

  @override
  Object? invoke(DismissIntent intent) {
    _controller.handleBack();
    return null;
  }
}
