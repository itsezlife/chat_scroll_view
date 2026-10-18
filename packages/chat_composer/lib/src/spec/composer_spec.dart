import 'package:chat_composer/src/menu/composer_formatting_option.dart';
import 'package:chat_composer/src/spec/action_descriptor.dart';
import 'package:chat_composer/src/spec/composer_header.dart';
import 'package:chat_composer/src/spec/composer_panel.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show BuildContext;

/// The host's dialog that asks for a link's URL: completes with the URL the
/// user entered, or null when they cancelled.
///
/// [context] is the composer's, so a dialog can be pushed on its navigator.
/// [currentUrl] is the target of the link the selection already touches (the
/// dialog edits it), or null when the selection holds none (the dialog
/// creates one).
typedef ComposerLinkPrompt =
    Future<String?> Function(BuildContext context, String? currentUrl);

/// Takes the system back button ahead of the soft keyboard and returns the
/// function that gives it back.
///
/// The soft keyboard consumes Back before Flutter's own dispatch sees it, so a
/// menu that wants Back to close it (and the keyboard to stay) needs the
/// host's platform hook. The composer calls this when the selection menu opens
/// and calls the returned function when it closes; [onBack] closes the menu
/// and completes with true.
typedef ComposerBackPriority =
    VoidCallback Function(ValueGetter<Future<bool>> onBack);

/// The host's declarative description of the composer for one moment: which
/// header, which panel, which actions, and whether it accepts input.
///
/// The host rebuilds it from chat state (permissions, reply target, draft,
/// connectivity) and passes it to `ComposerView`, which animates from the
/// previous spec to this one. The composer holds no mode of its own: replying
/// or editing is a [header] the host sets, restricted or recording is a
/// [panel] it names, and the buttons are [actions] it lists.
@immutable
final class ComposerSpec {
  /// Creates a spec. Action ids must be unique.
  ComposerSpec({
    this.header,
    this.panel = ComposerPanelId.text,
    this.actions = const [],
    this.enabled = true,
    this.busy = false,
    this.linkPrompt,
    this.formatting = ComposerFormattingOption.standard,
    this.backPriority,
  }) : assert(_uniqueIds(actions), 'two actions of a ComposerSpec share an id');

  /// What sits above the field, or null for no strip.
  final ComposerHeader? header;

  /// What occupies the input row.
  final ComposerPanelId panel;

  /// The actions, in the order they appear within their placement.
  final List<ActionDescriptor> actions;

  /// Whether the composer takes input at all. When false the field is
  /// read-only and every action is inert.
  final bool enabled;

  /// Whether a submit is in flight: the primary action is inert so it cannot
  /// fire twice, while the field stays editable.
  final bool busy;

  /// Asks the user for a link's URL when a command wants one (the link
  /// shortcut). Null leaves those commands inert: the composer owns no dialog,
  /// the host does.
  final ComposerLinkPrompt? linkPrompt;

  /// Which formatting items the selection menu may offer, in menu order
  /// whatever the order here. An empty set makes it a clipboard menu.
  ///
  /// An item is still left out where its command cannot apply (see
  /// `ComposerTextController.canApply`), and the link items where there is no
  /// [linkPrompt].
  final Set<ComposerFormattingOption> formatting;

  /// The host's hook for taking Back ahead of the soft keyboard while the
  /// selection menu is open; null leaves Back to Flutter's own dispatch.
  final ComposerBackPriority? backPriority;

  /// The visible actions at [placement], in spec order.
  List<ActionDescriptor> visibleActions(ActionPlacement placement) => [
    for (final action in actions)
      if (action.visible && action.placement == placement) action,
  ];

  /// The action the submit shortcut invokes: the first visible primary one.
  ActionDescriptor? get primaryAction {
    for (final action in actions) {
      if (action.visible && action.primary) return action;
    }
    return null;
  }

  static bool _uniqueIds(List<ActionDescriptor> actions) =>
      actions.map((action) => action.id).toSet().length == actions.length;
}
