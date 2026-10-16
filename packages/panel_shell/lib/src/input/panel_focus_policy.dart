import 'package:flutter/widgets.dart';

/// What takes focus when the panel becomes visible and where focus returns
/// when it goes away.
///
/// A keyboard-replacement panel usually wants [none]: the composer keeps its
/// place. A popup that a keyboard user opens wants [focusOnOpen] with the
/// composer's node as [restoreTarget].
@immutable
final class PanelFocusPolicy {
  /// A policy.
  const PanelFocusPolicy({this.focusOnOpen = false, this.restoreTarget});

  /// Moves nothing: the panel never takes or gives focus.
  static const PanelFocusPolicy none = PanelFocusPolicy();

  /// Whether the shell moves focus to its first focusable control when the
  /// panel becomes visible.
  final bool focusOnOpen;

  /// The node that gets focus back when the panel stops being visible while
  /// focus was inside it. Null leaves focus where the framework puts it.
  final FocusNode? restoreTarget;
}
