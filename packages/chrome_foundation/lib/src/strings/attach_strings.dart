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
    required this.captionPlaceholder,
    required this.sendAction,
    required this.moreOptions,
    required this.sendSilently,
    required this.schedule,
    required this.sendWhenOnline,
    required this.captionAbove,
    required this.captionBelow,
    required this.openExternal,
    required this.sendAsFile,
    required this.sendAsFiles,
    required this.sendWithoutGrouping,
    required this.enableSpoiler,
    required this.disableSpoiler,
    required this.highQuality,
    required this.standardQuality,
    required this.sendInHd,
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

  /// The caption field's placeholder ("Add a caption…").
  final String captionPlaceholder;

  /// The send button's spoken label ("Send").
  final String sendAction;

  /// The spoken label of the header's overflow button ("More").
  final String moreOptions;

  /// The send menu's "Send without sound".
  final String sendSilently;

  /// The send menu's "Schedule message".
  final String schedule;

  /// The send menu's "Send when online".
  final String sendWhenOnline;

  /// The menu entry that moves the caption above the media.
  final String captionAbove;

  /// The menu entry that moves the caption below the media.
  final String captionBelow;

  /// The overflow entry that opens the system picker.
  final String openExternal;

  /// The overflow entry that sends one item as a file.
  final String sendAsFile;

  /// The overflow entry that sends the items as files.
  final String sendAsFiles;

  /// The overflow entry that sends each item on its own.
  final String sendWithoutGrouping;

  /// The overflow entry that hides the media under a spoiler.
  final String enableSpoiler;

  /// The overflow entry that removes the spoiler.
  final String disableSpoiler;

  /// The overflow entry that switches to high quality.
  final String highQuality;

  /// The overflow entry that switches back to standard quality.
  final String standardQuality;

  /// The overflow entry that sends in high quality now.
  final String sendInHd;
}
