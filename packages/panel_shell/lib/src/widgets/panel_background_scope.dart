import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/widgets.dart';

/// What the shell paints behind its column, for the chrome of a page that
/// paints a band of its own (a strip, a search field over the catalogue).
///
/// A presentation that puts the shell on glass gives the shell a transparent
/// background (`PanelShell.background`); a band painted in the panel tokens'
/// background would then cover the glass. The shell provides its background
/// here, and such a band paints [of] instead. Outside a shell (or under one
/// with no background of its own) [of] is the panel tokens' background.
class PanelBackgroundScope extends InheritedWidget {
  /// Provides [color] to [child].
  const PanelBackgroundScope({
    required this.color,
    required super.child,
    super.key,
  });

  /// The shell's background.
  final Color color;

  /// The background a band under [context] paints.
  static Color of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<PanelBackgroundScope>()
          ?.color ??
      ChromeThemeScope.panelOf(context).background;

  /// Whether the background a band paints is see-through.
  static bool isClearIn(BuildContext context) => of(context).a < 1;

  @override
  bool updateShouldNotify(PanelBackgroundScope oldWidget) =>
      oldWidget.color != color;
}
