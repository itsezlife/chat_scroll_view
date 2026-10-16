/// Strings of the panel: tab names, section titles, search copy and the
/// clear-recents confirmation and the recents menu.
///
/// Supplied by the host as part of `ChromeStrings`; this package ships no
/// translation. Members are required so a host cannot forget one.
final class PanelStrings {
  /// Panel strings with every member given.
  const PanelStrings({
    required this.tabLabel,
    required this.categoryTitle,
    required this.recentlyUsedTitle,
    required this.searchResultsTitle,
    required this.searchHint,
    required this.searchEmpty,
    required this.clearRecentsTitle,
    required this.clearRecentsMessage,
    required this.clearAction,
    required this.cancelAction,
    required this.copyAction,
    required this.removeRecentAction,
    required this.clearRecentAction,
  });

  /// The name of the panel page registered under [pageId]. Page ids are open
  /// (a host registers its own), so a host answers for every id it
  /// registered; an id it does not know should come back as itself rather
  /// than throw.
  final String Function(String pageId) tabLabel;

  /// The title of the category section registered under [categoryId], such as
  /// a group of the emoji catalogue (`smileys-emotion`, `flags`).
  ///
  /// Category ids come from the data, so they are open: an id the host does
  /// not know should come back as itself rather than throw.
  final String Function(String categoryId) categoryTitle;

  /// Title of the recently-used section.
  final String recentlyUsedTitle;

  /// Title of the keyword-hit section while searching.
  final String searchResultsTitle;

  /// Hint of the empty search field.
  final String searchHint;

  /// Placeholder shown when a search finds nothing.
  final String searchEmpty;

  /// Title of the clear-recents confirmation.
  final String clearRecentsTitle;

  /// Body of the clear-recents confirmation.
  final String clearRecentsMessage;

  /// Confirming action of the clear-recents confirmation.
  final String clearAction;

  /// Dismissing action of the clear-recents confirmation.
  final String cancelAction;

  /// Menu item that copies the content under the pointer to the clipboard.
  final String copyAction;

  /// Menu item that forgets one item of the recently-used list.
  final String removeRecentAction;

  /// Menu item that asks to clear the whole recently-used list; shown in the
  /// attention style. Answered by the clear-recents confirmation
  /// ([clearRecentsTitle], [clearRecentsMessage], [clearAction]).
  final String clearRecentAction;
}
