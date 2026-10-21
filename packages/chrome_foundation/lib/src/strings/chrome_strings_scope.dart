import 'package:chrome_foundation/src/strings/chrome_strings.dart';
import 'package:chrome_foundation/src/strings/composer_strings.dart';
import 'package:chrome_foundation/src/strings/edit_menu_strings.dart';
import 'package:chrome_foundation/src/strings/formatting_strings.dart';
import 'package:chrome_foundation/src/strings/panel_strings.dart';
import 'package:chrome_foundation/src/strings/semantics_strings.dart';
import 'package:flutter/widgets.dart';

/// The **chrome strings scope**: supplies [ChromeStrings] to the subtree.
///
/// Required. A lookup with no scope above it throws in debug builds; there is
/// no default language to fall back to. The host places one above every
/// chrome widget and rebuilds it with new strings when its locale changes.
///
/// A nested scope replaces the strings for its subtree wholesale.
class ChromeStringsScope extends InheritedWidget {
  /// A scope supplying [strings] to [child].
  const ChromeStringsScope({
    required this.strings,
    required super.child,
    super.key,
  });

  /// The strings below this scope.
  final ChromeStrings strings;

  /// The strings at [context].
  ///
  /// Throws a [FlutterError] in debug builds when no scope exists.
  static ChromeStrings of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<ChromeStringsScope>();
    assert(() {
      if (scope == null) {
        throw FlutterError.fromParts([
          ErrorSummary('No ChromeStringsScope above this context.'),
          ErrorDescription(
            'Chrome widgets require a ChromeStringsScope; the package ships '
            'no default language.',
          ),
          ErrorHint(
            'Wrap the chrome in a ChromeStringsScope whose ChromeStrings '
            'come from the host localisation.',
          ),
          context.describeElement('The context used was'),
        ]);
      }
      return true;
    }(), 'No ChromeStringsScope above this context.');
    return scope!.strings;
  }

  /// The panel strings at [context]; see [of].
  static PanelStrings panelOf(BuildContext context) => of(context).panel;

  /// The composer strings at [context]; see [of].
  static ComposerStrings composerOf(BuildContext context) =>
      of(context).composer;

  /// The formatting strings at [context]; see [of].
  static FormattingStrings formattingOf(BuildContext context) =>
      of(context).formatting;

  /// The pointer menu strings at [context]; see [of].
  static EditMenuStrings editMenuOf(BuildContext context) =>
      of(context).editMenu;

  /// The semantics strings at [context]; see [of].
  static SemanticsStrings semanticsOf(BuildContext context) =>
      of(context).semantics;

  @override
  bool updateShouldNotify(ChromeStringsScope oldWidget) =>
      !identical(strings, oldWidget.strings);
}
