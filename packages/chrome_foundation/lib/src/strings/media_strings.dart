/// Strings of a message's media: what a screen reader hears for each item
/// and a link preview card, and the words a file row shows.
///
/// Supplied by the host as part of `ChromeStrings`; this package ships no
/// translation. Sizes, durations and progress are functions so a host can
/// apply its language's number and unit forms.
final class MediaStrings {
  /// Media strings with every member given.
  const MediaStrings({
    required this.photoKind,
    required this.videoKind,
    required this.animationKind,
    required this.fileKind,
    required this.duration,
    required this.size,
    required this.downloadProgress,
    required this.downloadAction,
    required this.cancelDownloadAction,
    required this.optionsAction,
    required this.pagePreview,
    required this.fileProgress,
    required this.fileInfo,
    required this.fileDownload,
    required this.fileOpenWith,
    required this.fileCancel,
  });

  /// A photo as a screen reader names it.
  final String photoKind;

  /// A video as a screen reader names it.
  final String videoKind;

  /// An animation (a GIF) as a screen reader names it.
  final String animationKind;

  /// A file, or any other item, as a screen reader names it.
  final String fileKind;

  /// A playback length, as spoken and as a badge shows it.
  final String Function(Duration duration) duration;

  /// A byte count, as spoken and as a file row shows it.
  final String Function(int bytes) size;

  /// A download's progress as spoken, 0 to 1, or null while it is not
  /// measured.
  final String Function(double? fraction) downloadProgress;

  /// The spoken action of an item's status control while it offers the
  /// download (the retry).
  final String downloadAction;

  /// The spoken action of an item's status control while it loads.
  final String cancelDownloadAction;

  /// The spoken action of an item's options affordance.
  final String optionsAction;

  /// What a link preview card's node starts with, before the page's title
  /// and text.
  final String pagePreview;

  /// A file row's info line while bytes arrive, from the two sizes already
  /// formatted by [size]: received, then total.
  final String Function(String received, String total) fileProgress;

  /// A file row's info line at rest, from the formatted size and the file's
  /// extension (upper case), either of which may be missing.
  final String Function(String? size, String? extension) fileInfo;

  /// A file row's link line while the file is not downloaded.
  final String fileDownload;

  /// A file row's link line once the file is downloaded.
  final String fileOpenWith;

  /// A file row's link line while the file downloads.
  final String fileCancel;
}
