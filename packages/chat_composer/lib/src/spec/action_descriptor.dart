import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/widgets.dart';

/// Which side of the panel an action sits on, in reading direction.
///
/// Leading is the start edge (left in left-to-right text), trailing the end
/// edge. The composer mirrors both for right-to-left text.
enum ActionPlacement {
  /// Before the panel, at the start edge.
  leading,

  /// After the panel, at the end edge.
  trailing,
}

/// Builds a widget around the rendered button of an action.
///
/// [button] is the composer's own button for the action; the result replaces
/// it in the row, so a wrapper keeps it as (a descendant of) what it returns.
typedef ActionWrap = Widget Function(BuildContext context, Widget button);

/// One action of the composer, described as data: the composer lays it out
/// and animates it, the host decides what it is and what tapping does.
///
/// Typical actions are the panel toggle, attach, voice or send, scheduled and
/// silent send, a bot menu and a slow-mode timer, but the composer knows none
/// of them. Two descriptors in a spec with the same [id] are one action: a
/// later spec that keeps the [id] and changes [icon] morphs the glyph in
/// place, so a host swaps send for voice by keeping one id.
@immutable
final class ActionDescriptor {
  /// Creates an action. The [semanticLabel] is required: every action must
  /// be announced by assistive technology, and the composer has no default
  /// language to guess one from. Hosts take it from
  /// `ChromeStrings.composer`.
  const ActionDescriptor({
    required this.id,
    required this.icon,
    required this.semanticLabel,
    this.placement = ActionPlacement.trailing,
    this.enabled = true,
    this.visible = true,
    this.primary = false,
    this.active = false,
    this.onTap,
    this.wrap,
    this.fill,
    this.onFill,
    this.iconSize,
  }) : assert(id != '', 'an action id must not be empty'),
       assert(semanticLabel != '', 'an action needs a semantic label');

  /// Stable identity of the action within a spec.
  final String id;

  /// The semantic icon, drawn through the chrome icon registry.
  final ChromeIconId icon;

  /// What assistive technology announces for the action.
  final String semanticLabel;

  /// Which edge the action sits on.
  final ActionPlacement placement;

  /// Whether the action reacts. A disabled action is drawn dimmed and
  /// announced as disabled.
  final bool enabled;

  /// Whether the action takes part in layout at all.
  final bool visible;

  /// Whether this is the action that submits the composer: it is drawn
  /// emphasised, the submit shortcut invokes it, and it is disabled while the
  /// spec is busy. At most one action of a spec should be primary; the first
  /// visible one wins.
  final bool primary;

  /// Whether the action is in its active, on or selected state: its glyph is
  /// drawn in the accent colour and it is announced as selected. A toggle that
  /// has switched something on says so with this; the glyph itself stays the
  /// same, so no second icon is needed for the state.
  final bool active;

  /// Called on tap, click or keyboard activation. Null makes the action
  /// inert.
  final VoidCallback? onTap;

  /// A widget the composer builds around the rendered button, or null.
  ///
  /// The composer knows nothing about what the host needs around one of its
  /// actions: a hover region, a tooltip, a drag target, a measuring probe.
  /// Rather than a field for each, the host wraps the button itself. The
  /// wrapper takes part in layout as the action does (an action that is not
  /// visible is not wrapped), receives the pointer events the button would, and is
  /// rebuilt with the spec.
  final ActionWrap? wrap;

  /// Disc colour of a primary action drawn as a disc, in place of the send
  /// colour. With it the action is not dimmed when disabled: the host passes
  /// the disabled colours itself (a web-style grey disc, say).
  final Color? fill;

  /// Glyph colour on [fill]; null keeps the on-send colour.
  final Color? onFill;

  /// Glyph size; null keeps the composer's action icon size.
  final double? iconSize;

  /// Whether a tap would do anything: visible, enabled and given a handler.
  bool get isTappable => visible && enabled && onTap != null;

  /// A copy with the named fields replaced.
  ActionDescriptor copyWith({
    ChromeIconId? icon,
    String? semanticLabel,
    ActionPlacement? placement,
    bool? enabled,
    bool? visible,
    bool? primary,
    bool? active,
    VoidCallback? onTap,
    ActionWrap? wrap,
    Color? fill,
    Color? onFill,
    double? iconSize,
  }) => ActionDescriptor(
    id: id,
    icon: icon ?? this.icon,
    semanticLabel: semanticLabel ?? this.semanticLabel,
    placement: placement ?? this.placement,
    enabled: enabled ?? this.enabled,
    visible: visible ?? this.visible,
    primary: primary ?? this.primary,
    active: active ?? this.active,
    onTap: onTap ?? this.onTap,
    wrap: wrap ?? this.wrap,
    fill: fill ?? this.fill,
    onFill: onFill ?? this.onFill,
    iconSize: iconSize ?? this.iconSize,
  );
}
