import 'package:flutter/widgets.dart';

/// How wide the window is, in three classes a web policy takes its layout
/// and presentation from: sizes, the side a menu prefers, whether a panel
/// docks.
///
/// The class is the window's, not the device's: a desktop browser narrowed
/// to a phone's width is [compact] and keeps its mouse (see
/// `ChromeInputClass` for the other axis). It is live: [of] reads the size
/// from `MediaQuery`, so a reader rebuilds on a resize and sees a new class
/// once the resize crosses a bound.
///
/// The web is the reader this is written for. A host may hand it to any
/// platform's policy; nothing in the package picks a policy from it.
enum ChromeWidthClass {
  /// No wider than [compactMaxWidth]: a phone, or a window narrowed to one.
  compact,

  /// Wider than [compactMaxWidth], no wider than [mediumMaxWidth].
  medium,

  /// Wider than [mediumMaxWidth].
  expanded;

  /// The widest a [compact] window is, in logical pixels. Inclusive: 600 is
  /// compact, 601 is not.
  static const double compactMaxWidth = 600;

  /// The widest a [medium] window is, in logical pixels. Inclusive: 925 is
  /// medium, 926 expanded.
  static const double mediumMaxWidth = 925;

  /// The widest a landscape phone is, in logical pixels, for
  /// `landscapePhoneIsCompact`.
  static const double landscapePhoneMaxWidth = 950;

  /// The tallest a landscape phone is, in logical pixels, for
  /// `landscapePhoneIsCompact`.
  static const double landscapePhoneMaxHeight = 450;

  /// The class of a window of [size].
  ///
  /// With [landscapePhoneIsCompact], a window no wider than
  /// [landscapePhoneMaxWidth] and no taller than [landscapePhoneMaxHeight]
  /// is [compact] whatever its width, so a phone turned on its side keeps
  /// the phone's layout. Off by default: then the width alone decides, and
  /// such a window is [medium] or [expanded].
  static ChromeWidthClass fromSize(
    Size size, {
    bool landscapePhoneIsCompact = false,
  }) {
    if (landscapePhoneIsCompact &&
        size.width <= landscapePhoneMaxWidth &&
        size.height <= landscapePhoneMaxHeight) {
      return compact;
    }
    if (size.width <= compactMaxWidth) return compact;
    if (size.width <= mediumMaxWidth) return medium;
    return expanded;
  }

  /// The class of the window at [context]: the `MediaQuery` size, with the
  /// nearest [ChromeWidthClassScope]'s option (off without one).
  ///
  /// Depends on the `MediaQuery` size and on the scope. A reader that wants
  /// to act only on a change (a diagnostics event, a re-layout) compares
  /// the value with the one it last saw.
  static ChromeWidthClass of(BuildContext context) => fromSize(
    MediaQuery.sizeOf(context),
    landscapePhoneIsCompact: ChromeWidthClassScope._landscapePhoneIsCompactOf(
      context,
    ),
  );

  /// Whether this is [compact].
  bool get isCompact => this == compact;
}

/// The host's width class option for a subtree: whether a landscape phone
/// counts as [ChromeWidthClass.compact].
///
/// Optional: without a scope the width alone decides. Scopes nest; the
/// nearest wins.
class ChromeWidthClassScope extends InheritedWidget {
  /// An option for [child].
  const ChromeWidthClassScope({
    required this.landscapePhoneIsCompact,
    required super.child,
    super.key,
  });

  /// Whether a window no wider than
  /// [ChromeWidthClass.landscapePhoneMaxWidth] and no taller than
  /// [ChromeWidthClass.landscapePhoneMaxHeight] is compact.
  final bool landscapePhoneIsCompact;

  static bool _landscapePhoneIsCompactOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<ChromeWidthClassScope>()
          ?.landscapePhoneIsCompact ??
      false;

  @override
  bool updateShouldNotify(ChromeWidthClassScope oldWidget) =>
      landscapePhoneIsCompact != oldWidget.landscapePhoneIsCompact;
}
