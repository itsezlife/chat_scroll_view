import 'package:chat_scroll_view/src/chat_widgets/chat_scroll_view.dart';
import 'package:flutter/widgets.dart';

/// Marks the subtree the viewport builds as its **floating header**.
///
/// [ChatScrollView.dateSeparatorBuilder] serves both the inline date
/// separator above the first message of each group and the floating header.
/// The viewport wraps only the floating header in this marker, so a widget
/// the builder returns can ask [isInside] and style the floating header
/// differently without a second builder.
///
/// A subtree is either the floating header or an inline date separator for
/// its whole life: the viewport builds the two in separate slots and never
/// moves an element between them. The marker therefore carries no data,
/// never notifies, and [isInside] registers no dependency. A host
/// `GlobalKey` that reparents a separator subtree across the two roles
/// breaks this: descendants keep the answer they last read.
///
/// The viewport inserts the marker. Any subtree wrapped in one reports
/// itself as the floating header, inside a viewport or not.
final class ChatFloatingHeaderMarker extends InheritedWidget {
  /// Marks [child] as the floating header.
  const ChatFloatingHeaderMarker({required super.child, super.key});

  /// Whether [context] lies inside the floating header.
  ///
  /// `false` for inline date separators and for any context without a
  /// marker above it. Read it from the build context of a widget the
  /// separator builder returns: the builder's own `context` sits above the
  /// marker and always answers `false`.
  ///
  /// Non-dependent lookup: calling it never schedules a rebuild.
  static bool isInside(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ChatFloatingHeaderMarker>() !=
      null;

  @override
  bool updateShouldNotify(covariant ChatFloatingHeaderMarker oldWidget) =>
      false;
}
