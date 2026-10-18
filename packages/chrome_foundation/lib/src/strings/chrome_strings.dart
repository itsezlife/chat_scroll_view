import 'package:chrome_foundation/src/strings/composer_strings.dart';
import 'package:chrome_foundation/src/strings/edit_menu_strings.dart';
import 'package:chrome_foundation/src/strings/formatting_strings.dart';
import 'package:chrome_foundation/src/strings/panel_strings.dart';
import 'package:chrome_foundation/src/strings/semantics_strings.dart';

/// All **chrome strings**: grouped, host-provided text for the panel, the
/// composer, the formatting menu, the pointer menu and assistive technology.
///
/// Labels are never tokens and no package here owns a language: the host fills
/// this from its own localisation or server language packs and supplies it
/// through a `ChromeStringsScope`. English and Russian presets for tests and
/// demos live in `package:chrome_foundation/testing.dart`.
///
/// The UI locale is independent of the search language set.
final class ChromeStrings {
  /// Strings made of the five groups.
  const ChromeStrings({
    required this.panel,
    required this.composer,
    required this.formatting,
    required this.editMenu,
    required this.semantics,
  });

  /// Panel copy.
  final PanelStrings panel;

  /// Composer copy.
  final ComposerStrings composer;

  /// Formatting menu and list copy.
  final FormattingStrings formatting;

  /// Pointer menu copy of the composer's field.
  final EditMenuStrings editMenu;

  /// Announcements and labels for assistive technology.
  final SemanticsStrings semantics;
}
