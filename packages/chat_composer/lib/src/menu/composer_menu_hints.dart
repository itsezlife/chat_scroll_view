import 'package:flutter/foundation.dart';

/// What a row of the pointer menu does, and so which row it is.
enum ComposerMenuAction {
  /// Undo the last edit.
  undo,

  /// Redo the edit undone last.
  redo,

  /// Cut the selection.
  cut,

  /// Copy the selection.
  copy,

  /// Paste the clipboard.
  paste,

  /// Paste the clipboard's plain text (an addition: the reference client has
  /// the key only).
  pastePlain,

  /// Delete the selection.
  delete,

  /// Select the whole text.
  selectAll,

  /// The Formatting submenu.
  formatting,

  /// Bold.
  bold,

  /// Italic.
  italic,

  /// Underline.
  underline,

  /// Strikethrough.
  strikethrough,

  /// Quote the selected lines.
  quote,

  /// Monospace (inline code).
  monospace,

  /// Spoiler.
  spoiler,

  /// A fenced code block (an addition).
  codeBlock,

  /// A bullet list (an addition).
  bulletList,

  /// A numbered list (an addition).
  numberedList,

  /// Create a link.
  createLink,

  /// Edit the link the selection or the pointer touches.
  editLink,

  /// Remove the link (an addition).
  removeLink,

  /// Clear the formatting.
  clearFormatting,

  /// The Spelling submenu.
  spelling,

  /// Add the word to the user dictionary.
  addToDictionary,

  /// Ignore the word.
  ignoreWord,

  /// Remove the word from the user dictionary.
  removeFromDictionary,
}

/// The shortcut text of each row of the pointer menu on one platform, as the
/// reference toolkit's `QKeySequence::NativeText` writes it: glyphs on macOS
/// (`⇧⌘Z`, Shift before Command), `Ctrl+Shift+Z` elsewhere.
///
/// The keys are the reference client's: Qt's standard keys for the edit rows
/// and the client's own for formatting. Redo differs per platform (`Ctrl+Y` on
/// Windows, `Ctrl+Shift+Z` on Linux). Rows the client has no key for (Delete,
/// the Formatting row itself, and the workspace's additions) have none.
///
/// **UNVERIFIED:** the macOS glyph form and the omission rule (Qt leaves a
/// hint out where the application registered the same key itself) come from
/// reading Qt's rules, not from a device.
final class ComposerMenuHints {
  const ComposerMenuHints._(this._apple, this._redo);

  /// The hints of [platform].
  factory ComposerMenuHints.forPlatform(TargetPlatform platform) =>
      switch (platform) {
        TargetPlatform.macOS ||
        TargetPlatform.iOS => const ComposerMenuHints._(true, '⇧⌘Z'),
        TargetPlatform.windows => const ComposerMenuHints._(false, 'Ctrl+Y'),
        _ => const ComposerMenuHints._(false, 'Ctrl+Shift+Z'),
      };

  final bool _apple;
  final String _redo;

  String _key(String key, {bool shift = false}) =>
      _apple ? '${shift ? '⇧' : ''}⌘$key' : 'Ctrl+${shift ? 'Shift+' : ''}$key';

  /// The shortcut text of [action], or null for a row with none.
  String? of(ComposerMenuAction action) => switch (action) {
    ComposerMenuAction.undo => _key('Z'),
    ComposerMenuAction.redo => _redo,
    ComposerMenuAction.cut => _key('X'),
    ComposerMenuAction.copy => _key('C'),
    ComposerMenuAction.paste => _key('V'),
    ComposerMenuAction.pastePlain => _key('V', shift: true),
    ComposerMenuAction.selectAll => _key('A'),
    ComposerMenuAction.bold => _key('B'),
    ComposerMenuAction.italic => _key('I'),
    ComposerMenuAction.underline => _key('U'),
    ComposerMenuAction.strikethrough => _key('X', shift: true),
    ComposerMenuAction.quote => _key('.', shift: true),
    ComposerMenuAction.monospace => _key('M', shift: true),
    ComposerMenuAction.spoiler => _key('P', shift: true),
    ComposerMenuAction.createLink || ComposerMenuAction.editLink => _key('K'),
    ComposerMenuAction.clearFormatting => _key('N', shift: true),
    ComposerMenuAction.delete ||
    ComposerMenuAction.formatting ||
    ComposerMenuAction.codeBlock ||
    ComposerMenuAction.bulletList ||
    ComposerMenuAction.numberedList ||
    ComposerMenuAction.removeLink ||
    ComposerMenuAction.spelling ||
    ComposerMenuAction.addToDictionary ||
    ComposerMenuAction.ignoreWord ||
    ComposerMenuAction.removeFromDictionary => null,
  };
}
