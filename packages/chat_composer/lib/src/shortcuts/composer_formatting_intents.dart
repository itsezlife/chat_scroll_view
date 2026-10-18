import 'package:content_model/content_model.dart';
import 'package:flutter/widgets.dart';

/// Asks the composer to toggle [style] over the selection: on, or off when the
/// whole selection is in it already.
///
/// Calls `ComposerTextController.toggleStyle`, the command the selection menu
/// calls too, so a shortcut over a collapsed caret does what the menu would
/// (nothing, except for the styles that cover whole lines). Does nothing when
/// the command would change nothing (`canApply`).
class ToggleStyleIntent extends Intent {
  /// Creates the intent for [style].
  const ToggleStyleIntent(this.style);

  /// The style to toggle.
  final EntityStyle style;
}

/// Asks the composer to toggle a code block over the lines the selection
/// touches; see `ComposerTextController.toggleCodeBlock`.
///
/// The default maps leave it unbound: the reference desktop client has no key
/// for it (its monospace key makes a block over several lines on its own).
class ToggleCodeBlockIntent extends Intent {
  /// Creates the intent.
  const ToggleCodeBlockIntent();
}

/// Asks the composer to link the selection: asks `ComposerSpec.linkPrompt`
/// for a URL and applies it with `ComposerTextController.applyLink`.
///
/// Does nothing without a prompt, or where the link could not be applied
/// (over code or a mention).
class ApplyLinkIntent extends Intent {
  /// Creates the intent.
  const ApplyLinkIntent();
}

/// Asks the composer to take the formatting off the selection; see
/// `ComposerTextController.clearFormatting`.
class ClearFormattingIntent extends Intent {
  /// Creates the intent.
  const ClearFormattingIntent();
}

/// Asks the composer to toggle the lines the selection touches into list
/// items of [listKind].
///
/// The composer answers it once lists are on; until then the key it is bound
/// to is left to the field.
class ToggleListIntent extends Intent {
  /// Creates the intent for [listKind].
  const ToggleListIntent(this.listKind);

  /// Bullet or numbered.
  final EntityListKind listKind;
}
