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
    required this.favouriteStickersTitle,
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
    required this.colorAllTitle,
    required this.gifsEmpty,
    required this.stickersEmpty,
    required this.gifsFailed,
    required this.retryAction,
  });

  /// The name of the panel page registered under [pageId]. Page ids are open
  /// (a host registers its own), so a host answers for every id it
  /// registered; an id it does not know should come back as itself rather
  /// than throw.
  final String Function(String pageId) tabLabel;

  /// The title of the category section registered under [categoryId], such as
  /// a section of the emoji grid (`people`, `symbols`).
  ///
  /// Category ids come from the data, so they are open: an id the host does
  /// not know should come back as itself rather than throw.
  final String Function(String categoryId) categoryTitle;

  /// Title of the recently-used section.
  final String recentlyUsedTitle;

  /// Title of the favourite stickers' section, and the name of its tab on the
  /// stickers page's strip.
  final String favouriteStickersTitle;

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

  /// Dismissing action: of the clear-recents confirmation, and the button
  /// beside the search field that leaves search where there is no back press.
  final String cancelAction;

  /// Menu item that copies the content under the pointer to the clipboard.
  final String copyAction;

  /// Menu item that forgets one item of the recently-used list.
  final String removeRecentAction;

  /// Menu item that asks to clear the whole recently-used list; shown in the
  /// attention style. Answered by the clear-recents confirmation
  /// ([clearRecentsTitle], [clearRecentsMessage], [clearAction]).
  final String clearRecentAction;

  /// The title of the picker that chooses one tone for every emoji, and the
  /// spoken label of the button that opens it.
  final String colorAllTitle;

  /// Placeholder of the GIF page when a search finds no clip, and when the
  /// page has no clip to list at all (no recents, and no provider).
  final String gifsEmpty;

  /// Placeholder of the stickers page when it has no sticker to list: no
  /// recents and no pack.
  final String stickersEmpty;

  /// Placeholder of the GIF page when its clips could not be loaded (offline,
  /// a busy server): shown with [retryAction].
  final String gifsFailed;

  /// Label of the button that tries a failed load of the GIF page again.
  final String retryAction;
}
