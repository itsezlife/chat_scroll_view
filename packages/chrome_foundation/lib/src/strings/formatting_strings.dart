/// Strings of the formatting surfaces: the selection menu's items, its
/// overflow page and the semantics labels of list items.
///
/// Supplied by the host as part of `ChromeStrings`; this package ships no
/// translation. The action labels are the visible text of the menu items and
/// double as their semantic labels. A menu item that is not offered (for
/// instance Quote on an already quoted selection) is the composer's decision,
/// not a string.
final class FormattingStrings {
  /// Formatting strings with every member given.
  const FormattingStrings({
    required this.quoteAction,
    required this.spoilerAction,
    required this.boldAction,
    required this.italicAction,
    required this.monoAction,
    required this.strikethroughAction,
    required this.underlineAction,
    required this.createLinkAction,
    required this.editLinkAction,
    required this.removeLinkAction,
    required this.codeBlockAction,
    required this.bulletListAction,
    required this.numberedListAction,
    required this.clearFormattingAction,
    required this.moreAction,
    required this.backAction,
    required this.bulletListItem,
    required this.numberedListItem,
  });

  /// Menu item that turns the selection into a quote.
  final String quoteAction;

  /// Menu item that hides the selection behind a spoiler.
  final String spoilerAction;

  /// Menu item for bold.
  final String boldAction;

  /// Menu item for italic.
  final String italicAction;

  /// Menu item for monospace (inline code).
  final String monoAction;

  /// Menu item for strikethrough.
  final String strikethroughAction;

  /// Menu item for underline.
  final String underlineAction;

  /// Menu item that makes the selection a link.
  final String createLinkAction;

  /// Menu item that edits the link under the selection.
  final String editLinkAction;

  /// Menu item that turns the link under the selection back into plain text.
  final String removeLinkAction;

  /// Menu item that turns the selection into a fenced code block.
  final String codeBlockAction;

  /// Menu item that makes the selected lines a bullet list.
  final String bulletListAction;

  /// Menu item that makes the selected lines a numbered list.
  final String numberedListAction;

  /// Menu item that clears the formatting of the selection ("Regular").
  final String clearFormattingAction;

  /// Label of the button that opens the overflow page of the menu.
  final String moreAction;

  /// Label of the row that returns from the overflow page to the main row.
  final String backAction;

  /// Semantics label of a bullet list item.
  final String bulletListItem;

  /// Semantics label of a numbered list item: `numberedListItem(3)`; [number]
  /// is the item's position as shown, counted from the list's start number.
  final String Function(int number) numberedListItem;
}
