/// Strings of the draft options overlay: the titles of its pages.
///
/// Supplied by the host as part of `ComposerStrings`; this package ships no
/// translation.
final class DraftOptionsStrings {
  /// Draft options strings with every member given.
  const DraftOptionsStrings({
    required this.linkTitle,
    required this.linkSubtitle,
  });

  /// Title of the link preview page.
  final String linkTitle;

  /// Subtitle of the link preview page, under [linkTitle] where the platform
  /// heads a page with both.
  final String linkSubtitle;
}
