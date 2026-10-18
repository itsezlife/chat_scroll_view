/// Strings of the pointer menu of the composer's text field: the edit rows,
/// the Formatting submenu and the workspace's additions to it.
///
/// Supplied by the host as part of `ChromeStrings`; this package ships no
/// translation. The wording is the reference desktop client's (Monospace,
/// Create link, Clear formatting), which is not the touch menu's (Mono, Create
/// Link, Regular), so the two menus read their own group
/// ([FormattingStrings] is the touch menu's).
///
/// **Mnemonics.** The reference toolkit marks an access letter with `&` in the
/// label (`&Undo`, `Cu&t`), and its menu draws that letter underlined; `&&` is
/// a literal ampersand. A label here may carry the mark, and the menu draws
/// it and strips it from the spoken label. A translation places the mark as
/// its own language's convention does, or leaves it out.
final class EditMenuStrings {
  /// Edit menu strings with every member given.
  const EditMenuStrings({
    required this.undoAction,
    required this.redoAction,
    required this.cutAction,
    required this.copyAction,
    required this.pasteAction,
    required this.deleteAction,
    required this.selectAllAction,
    required this.formattingMenu,
    required this.boldAction,
    required this.italicAction,
    required this.underlineAction,
    required this.strikethroughAction,
    required this.quoteAction,
    required this.monospaceAction,
    required this.spoilerAction,
    required this.createLinkAction,
    required this.editLinkAction,
    required this.clearFormattingAction,
    required this.pastePlainAction,
    required this.codeBlockAction,
    required this.removeLinkAction,
    required this.bulletListAction,
    required this.numberedListAction,
  });

  /// Row that undoes the last edit.
  final String undoAction;

  /// Row that redoes the edit undone last.
  final String redoAction;

  /// Row that cuts the selection to the clipboard.
  final String cutAction;

  /// Row that copies the selection.
  final String copyAction;

  /// Row that pastes the clipboard.
  final String pasteAction;

  /// Row that deletes the selection without the clipboard.
  final String deleteAction;

  /// Row that selects the whole text.
  final String selectAllAction;

  /// Row that opens the formatting submenu.
  final String formattingMenu;

  /// Formatting row for bold.
  final String boldAction;

  /// Formatting row for italic.
  final String italicAction;

  /// Formatting row for underline.
  final String underlineAction;

  /// Formatting row for strikethrough.
  final String strikethroughAction;

  /// Formatting row that quotes the selected lines.
  final String quoteAction;

  /// Formatting row for monospace (inline code).
  final String monospaceAction;

  /// Formatting row that hides the selection behind a spoiler.
  final String spoilerAction;

  /// Formatting row that links the selection.
  final String createLinkAction;

  /// Formatting row that edits the link the selection or the pointer touches.
  final String editLinkAction;

  /// Formatting row that takes every format off the selection.
  final String clearFormattingAction;

  /// Addition: row that pastes the clipboard's plain text, without its
  /// formatting. The reference client has the key only.
  final String pastePlainAction;

  /// Addition: formatting row for a fenced code block.
  final String codeBlockAction;

  /// Addition: formatting row that turns the touched link back into text.
  final String removeLinkAction;

  /// Addition: formatting row that makes the selected lines a bullet list.
  final String bulletListAction;

  /// Addition: formatting row that makes the selected lines a numbered list.
  final String numberedListAction;
}
