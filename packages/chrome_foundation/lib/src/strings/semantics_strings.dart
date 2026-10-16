/// Strings spoken or announced by assistive technology: panel state changes,
/// search result counts and action labels with no visible text.
///
/// Supplied by the host as part of `ChromeStrings`; this package ships no
/// translation. Plural and data-dependent wording are functions so a host can
/// apply its language's rules.
final class SemanticsStrings {
  /// Semantics strings with every member given.
  const SemanticsStrings({
    required this.panelOpened,
    required this.panelClosed,
    required this.pageSelected,
    required this.searchFieldLabel,
    required this.searchResultCount,
    required this.backspaceAction,
    required this.variantsAction,
  });

  /// Announced when the panel opens.
  final String panelOpened;

  /// Announced when the panel closes.
  final String panelClosed;

  /// Announced when the page named [pageLabel] (already a display name, not a
  /// page id) becomes the selected one.
  final String Function(String pageLabel) pageSelected;

  /// Semantic label of the search field.
  final String searchFieldLabel;

  /// Announced when a search settles on [count] results; `0` means none.
  /// Plural rules are the host language's.
  final String Function(int count) searchResultCount;

  /// Semantic label of the backspace action.
  final String backspaceAction;

  /// Label of the custom action that opens an item's variants (skin tones).
  final String variantsAction;
}
