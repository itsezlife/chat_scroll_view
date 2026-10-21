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
/// items of [listKind]; see `ComposerTextController.toggleList`.
///
/// The composer answers it only for a text controller with `lists` on;
/// otherwise the key it is bound to is left to the field.
class ToggleListIntent extends Intent {
  /// Creates the intent for [listKind].
  const ToggleListIntent(this.listKind);

  /// Bullet or numbered.
  final EntityListKind listKind;
}

/// Asks the composer to move the list items the selection touches one level
/// deeper; see `ComposerTextController.indentListItems`. Tab by default.
///
/// Answered only where the selection touches an item that can move, so Tab
/// keeps moving focus everywhere else.
class IndentListItemsIntent extends Intent {
  /// Creates the intent.
  const IndentListItemsIntent();
}

/// Asks the composer to move the list items the selection touches one level
/// out; see `ComposerTextController.outdentListItems`. Shift+Tab by default.
class OutdentListItemsIntent extends Intent {
  /// Creates the intent.
  const OutdentListItemsIntent();
}

/// Asks the composer for a soft break: a line break inside the list item at
/// the caret; see `ComposerTextController.insertSoftBreak`. Shift+Enter by
/// default.
class InsertSoftBreakIntent extends Intent {
  /// Creates the intent.
  const InsertSoftBreakIntent();
}

/// Asks the composer to outdent the list item the caret is at the start of,
/// and to take it out of the list when it has no level left; see
/// `ComposerTextController.outdentOrExitListItem`. Backspace by default.
///
/// The soft keyboard's Backspace arrives as an edit of the text and the
/// controller recognises it there; this intent is for the key that changes
/// nothing when the item is the first line, and for hardware keys.
class OutdentOrExitListItemIntent extends Intent {
  /// Creates the intent.
  const OutdentOrExitListItemIntent();
}
