import 'package:meta/meta.dart';

/// The words a file row shows, from the host: the file size, the progress
/// while bytes arrive, the info line and the link line's labels.
///
/// A host passes its localized wording through
/// `MediaFileStackPolicy.copyWith(strings: …)`; [english] is the default so
/// a row reads without one. The row never builds a size or a label from a
/// literal of its own.
@immutable
final class MediaFileStrings {
  /// Strings from the given functions and labels.
  const MediaFileStrings({
    required this.size,
    required this.progress,
    required this.info,
    required this.download,
    required this.openWith,
    required this.cancel,
  });

  /// English: `"512 B"`, `"1.2 KB"`, `"3.4 MB"`, `"1.25 GB"`; `"a / b"`;
  /// `"<size> <EXT>"`; DOWNLOAD, OPEN WITH, CANCEL.
  static const english = MediaFileStrings(
    size: _englishSize,
    progress: _slashProgress,
    info: _spacedInfo,
    download: 'DOWNLOAD',
    openWith: 'OPEN WITH',
    cancel: 'CANCEL',
  );

  /// A byte count as the row shows it.
  final String Function(int bytes) size;

  /// The progress while bytes arrive, from the two sizes already formatted
  /// by [size]: received, then total.
  final String Function(String received, String total) progress;

  /// The info line at rest from the formatted size and the file's
  /// extension (upper case), either of which may be missing.
  final String Function(String? size, String? extension) info;

  /// The link line's label while the file is not downloaded.
  final String download;

  /// The link line's label once the file is downloaded.
  final String openWith;

  /// The link line's label while the file downloads.
  final String cancel;

  /// A copy with the given strings replaced.
  MediaFileStrings copyWith({
    String Function(int bytes)? size,
    String Function(String received, String total)? progress,
    String Function(String? size, String? extension)? info,
    String? download,
    String? openWith,
    String? cancel,
  }) => MediaFileStrings(
    size: size ?? this.size,
    progress: progress ?? this.progress,
    info: info ?? this.info,
    download: download ?? this.download,
    openWith: openWith ?? this.openWith,
    cancel: cancel ?? this.cancel,
  );

  @override
  bool operator ==(Object other) =>
      other is MediaFileStrings &&
      other.size == size &&
      other.progress == progress &&
      other.info == info &&
      other.download == download &&
      other.openWith == openWith &&
      other.cancel == cancel;

  @override
  int get hashCode =>
      Object.hash(size, progress, info, download, openWith, cancel);
}

String _englishSize(int bytes) => switch (bytes) {
  < 1024 => '$bytes B',
  < 1024 * 1024 => '${(bytes / 1024).toStringAsFixed(1)} KB',
  < 1024 * 1024 * 1024 => '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB',
  _ => '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB',
};

String _slashProgress(String received, String total) => '$received / $total';

String _spacedInfo(String? size, String? extension) =>
    [?size, ?extension].join(' ');
