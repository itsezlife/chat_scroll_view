import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:flutter/material.dart';

/// Material window-size classes (logical px). Layout follows *available
/// width*, not OS — a 400px desktop window lays out like a phone.
const double _kMediumWidth = 600;
const double _kExpandedWidth = 840;

/// Compact / medium / expanded [ChatScrollThemeData] presets.
///
/// Const so [ChatScrollTheme] can keep the same instance across rebuilds
/// at a given breakpoint (`updateShouldNotify` is identity).
abstract final class DemoChatThemes {
  /// Phone-width: full-bleed column, incoming start / outgoing end.
  static const compact = ChatScrollThemeData(message: _compactMessage);

  /// Tablet-width: capped, centred column.
  static const medium = ChatScrollThemeData(message: _mediumMessage);

  /// Desktop-width: wider capped, centred column.
  static const expanded = ChatScrollThemeData(message: _expandedMessage);

  static const _compactMessage = ChatMessageThemeData.fallback;

  static const _mediumMessage = ChatMessageThemeData(
    contentMaxWidth: 560,
    bubbleMaxWidth: 480,
    columnPlacement: ChatMessageColumnPlacement.center,
  );

  static const _expandedMessage = ChatMessageThemeData(
    contentMaxWidth: 720,
    bubbleMaxWidth: 560,
    columnPlacement: ChatMessageColumnPlacement.center,
  );
}

/// Picks a [ChatScrollThemeData] for [width] using Material size classes.
ChatScrollThemeData demoScrollThemeForWidth(double width) {
  if (width >= _kExpandedWidth) return DemoChatThemes.expanded;
  if (width >= _kMediumWidth) return DemoChatThemes.medium;
  return DemoChatThemes.compact;
}

/// Applies [demoScrollThemeForWidth] from [MediaQuery.sizeOf].
///
/// Place **below** `MaterialApp` so [MediaQuery] is in scope. Rebuilds only
/// when the window size changes; the inherited [ChatScrollThemeData] is a
/// const preset, so descendants are not notified on same-breakpoint rebuilds.
class DemoChatTheme extends StatelessWidget {
  /// Wraps [child] with a width-resolved [ChatScrollTheme].
  const DemoChatTheme({required this.child, super.key});

  /// Subtree that reads [ChatScrollTheme.messageOf].
  final Widget child;

  @override
  Widget build(BuildContext context) => ChatScrollTheme(
    data: demoScrollThemeForWidth(MediaQuery.widthOf(context)),
    child: child,
  );
}
