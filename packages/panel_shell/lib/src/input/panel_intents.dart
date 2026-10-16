import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Asks the shell to select the page [pageId].
///
/// Tab taps and keyboard activation invoke this intent, so a host that wants
/// to observe or veto a selection overrides one `Action` instead of
/// subclassing widgets.
class PanelSelectPageIntent extends Intent {
  /// An intent to select [pageId].
  const PanelSelectPageIntent(this.pageId);

  /// The page to select.
  final String pageId;
}

/// Asks the shell to open search and focus its field.
class PanelSearchIntent extends Intent {
  /// An intent to open search.
  const PanelSearchIntent();
}

/// The default shortcut maps of the shell.
///
/// Escape is Flutter's [DismissIntent]. The shell's action closes search while
/// it is open and otherwise forwards the intent to the nearest enclosing
/// handler, so a popup that hosts the shell closes on the second press. The
/// popup must bind Escape itself: `Shortcuts` looks up the action nearest the
/// focused widget only, so the order search first, then the popup, comes from
/// that forwarding and not from key-event bubbling.
abstract final class PanelShortcuts {
  /// Escape dismisses search; Control or Command plus F opens it.
  static const Map<ShortcutActivator, Intent> standard =
      <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
        SingleActivator(LogicalKeyboardKey.keyF, control: true):
            PanelSearchIntent(),
        SingleActivator(LogicalKeyboardKey.keyF, meta: true):
            PanelSearchIntent(),
      };
}
