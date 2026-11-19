/// Strings of the attach sheet's own chrome: the questions asked before a
/// selection is thrown away, and its stock page labels.
///
/// Supplied by the host as part of `ChromeStrings`; this package ships no
/// translation. Which question a platform asks is the sheet policy's; both
/// wordings live here.
final class AttachStrings {
  /// Attach strings with every member given.
  const AttachStrings({
    required this.discardSelectionTitle,
    required this.discardSelectionConfirm,
    required this.discardSelectionKeep,
    required this.cancelSelectionTitle,
    required this.cancelSelectionConfirm,
    required this.cancelSelectionKeep,
    required this.galleryTab,
    required this.filesTab,
    required this.permissionNeeded,
  });

  /// The question before a selection is dropped, in the "discard" wording
  /// ("Discard selection?").
  final String discardSelectionTitle;

  /// Its action that drops the selection ("Discard").
  final String discardSelectionConfirm;

  /// Its action that keeps the sheet open ("Cancel").
  final String discardSelectionKeep;

  /// The question in the "cancel" wording ("Cancel selection?").
  final String cancelSelectionTitle;

  /// Its action that drops the selection ("Yes").
  final String cancelSelectionConfirm;

  /// Its action that keeps the sheet open ("No").
  final String cancelSelectionKeep;

  /// The label of the stock Gallery page's tab.
  final String galleryTab;

  /// The label of the stock Files page's tab.
  final String filesTab;

  /// The spoken name of a tab's badge when its page lacks a permission.
  final String permissionNeeded;
}
