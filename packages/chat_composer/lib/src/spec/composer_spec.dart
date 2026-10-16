import 'package:chat_composer/src/spec/action_descriptor.dart';
import 'package:chat_composer/src/spec/composer_header.dart';
import 'package:chat_composer/src/spec/composer_panel.dart';
import 'package:flutter/foundation.dart';

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
