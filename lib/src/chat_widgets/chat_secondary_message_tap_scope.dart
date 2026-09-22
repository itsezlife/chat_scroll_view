import 'package:flutter/widgets.dart';

/// Ambient: whether the host opted into
/// [ChatScrollView.onSecondaryMessageTap].
///
/// Combined with
/// [ChatSelectionPolicy.secondaryMessageTapOwnsFullSlot]: under `$Desktop`,
/// per-body markdown must not claim secondary (right-click) — the viewport
/// owns the full message **slot** for the **message menu**. Under `$Mobile`,
/// secondary may still be wired, but Flutter’s adaptive **text selection
/// chrome** stays available.
final class ChatSecondaryMessageTapScope extends InheritedWidget {
  /// Creates a secondary-ownership scope for descendant markdown bodies.
  const ChatSecondaryMessageTapScope({
    required this.hostOwnsSecondary,
    required super.child,
    super.key,
  });

  /// Whether [ChatScrollView.onSecondaryMessageTap] is non-null.
  final bool hostOwnsSecondary;

  /// Whether an ancestor host owns secondary on the message slot.
  ///
  /// Defaults to false when no scope is in the tree. Callers that suppress
  /// text context menus must also check
  /// [ChatSelectionPolicy.secondaryMessageTapOwnsFullSlot].
  static bool hostOwnsSecondaryOf(BuildContext context, {bool listen = true}) {
    final scope = listen
        ? context
              .dependOnInheritedWidgetOfExactType<
                ChatSecondaryMessageTapScope
              >()
        : context.getInheritedWidgetOfExactType<ChatSecondaryMessageTapScope>();
    return scope?.hostOwnsSecondary ?? false;
  }

  @override
  bool updateShouldNotify(covariant ChatSecondaryMessageTapScope oldWidget) =>
      hostOwnsSecondary != oldWidget.hostOwnsSecondary;
}
