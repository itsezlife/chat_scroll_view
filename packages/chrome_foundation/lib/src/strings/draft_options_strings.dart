/// Strings of the draft options overlay: the titles of its pages and the
/// link page's rows.
///
/// Supplied by the host as part of `ComposerStrings`; this package ships no
/// translation.
final class DraftOptionsStrings {
  /// Draft options strings with every member given.
  const DraftOptionsStrings({
    required this.linkTitle,
    required this.linkSubtitle,
    required this.moveUp,
    required this.moveDown,
    required this.enlargePhoto,
    required this.shrinkPhoto,
    required this.enlargeVideo,
    required this.shrinkVideo,
    required this.applyChanges,
    required this.doNotPreview,
    required this.removePreview,
    required this.chooseLinkHint,
  });

  /// Title of the link preview page.
  final String linkTitle;

  /// Subtitle of the link preview page, under [linkTitle] where the platform
  /// heads a page with both.
  final String linkSubtitle;

  /// The position row while the card is below the text: it moves the card
  /// above.
  final String moveUp;

  /// The position row while the card is above the text: it moves the card
  /// below.
  final String moveDown;

  /// The size row while the page's photo is small.
  final String enlargePhoto;

  /// The size row while the page's photo is large.
  final String shrinkPhoto;

  /// The size row while the page's video is small.
  final String enlargeVideo;

  /// The size row while the page's video is large.
  final String shrinkVideo;

  /// The row that closes the overlay, the changes already applied.
  final String applyChanges;

  /// The destructive row that drops the preview, where the platform words
  /// it as a refusal.
  final String doNotPreview;

  /// The row that drops the preview, where the platform words it as a
  /// removal.
  final String removePreview;

  /// The divider text under the rows when the text has more than one link:
  /// a link in the preview can be chosen.
  final String chooseLinkHint;
}
