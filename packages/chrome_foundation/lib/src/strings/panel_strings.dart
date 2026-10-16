/// Strings of the panel: tab names, section titles, search copy and the
/// clear-recents confirmation.
///
/// Supplied by the host as part of `ChromeStrings`; this package ships no
/// translation. Members are required so a host cannot forget one.
final class PanelStrings {
  /// Panel strings with every member given.
  const PanelStrings({
    required this.tabLabel,
    required this.recentlyUsedTitle,
    required this.searchResultsTitle,
    required this.searchHint,
    required this.searchEmpty,
    required this.clearRecentsTitle,
    required this.clearRecentsMessage,
    required this.clearAction,
    required this.cancelAction,
  });

  /// The name of the panel page registered under [pageId]. Page ids are open
  /// (a host registers its own), so a host answers for every id it
  /// registered; an id it does not know should come back as itself rather
  /// than throw.
  final String Function(String pageId) tabLabel;

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
}
