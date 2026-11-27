import 'package:content_model/content_model.dart' show MediaItemKind;
import 'package:meta/meta.dart';

/// The words a screen reader hears for a message's media, from the host.
///
/// Each item is one node, labelled by [label]: its kind, then its duration
/// (a video, an animation that knows one) or its size (a file, or any item
/// not downloaded yet), then its progress while it loads. The node's actions
/// are named [download], [cancel] and [options]. A host passes its
/// localized wording through `MessageMediaPolicy.copyWith(semantics: …)`;
/// [english] is the default.
@immutable
final class MediaSemanticsStrings {
  /// Strings from the given functions and labels.
  const MediaSemanticsStrings({
    required this.kind,
    required this.duration,
    required this.size,
    required this.progress,
    required this.download,
    required this.cancel,
    required this.options,
  });

  /// English: Photo, Video, GIF, File; `1:05`; `3.4 MB`; `Downloading,
  /// 40%`; Download, Cancel download, More options.
  static const english = MediaSemanticsStrings(
    kind: _englishKind,
    duration: _clockDuration,
    size: _englishSize,
    progress: _englishProgress,
    download: 'Download',
    cancel: 'Cancel download',
    options: 'More options',
  );

  /// The item's kind as a screen reader says it.
  final String Function(MediaItemKind kind) kind;

  /// A playback length.
  final String Function(Duration duration) duration;

  /// A byte count.
  final String Function(int bytes) size;

  /// The progress of a download, 0 to 1, or null while it is not measured.
  final String Function(double? fraction) progress;

  /// The status control's action while it offers the download (the retry).
  final String download;

  /// The status control's action while the item loads.
  final String cancel;

  /// The options affordance's action.
  final String options;

  /// The node's label: [kind], then [duration] or [size] where the item
  /// has one, then [progress] while [loading].
  String label({
    required MediaItemKind kind,
    Duration? duration,
    int? size,
    bool loading = false,
    double? fraction,
  }) => [
    this.kind(kind),
    if (duration != null) this.duration(duration),
    if (size != null) this.size(size),
    if (loading) progress(fraction),
  ].join(', ');

  /// A copy with the given strings replaced.
  MediaSemanticsStrings copyWith({
    String Function(MediaItemKind kind)? kind,
    String Function(Duration duration)? duration,
    String Function(int bytes)? size,
    String Function(double? fraction)? progress,
    String? download,
    String? cancel,
    String? options,
  }) => MediaSemanticsStrings(
    kind: kind ?? this.kind,
    duration: duration ?? this.duration,
    size: size ?? this.size,
    progress: progress ?? this.progress,
    download: download ?? this.download,
    cancel: cancel ?? this.cancel,
    options: options ?? this.options,
  );

  @override
  bool operator ==(Object other) =>
      other is MediaSemanticsStrings &&
      other.kind == kind &&
      other.duration == duration &&
      other.size == size &&
      other.progress == progress &&
      other.download == download &&
      other.cancel == cancel &&
      other.options == options;

  @override
  int get hashCode =>
      Object.hash(kind, duration, size, progress, download, cancel, options);
}

String _englishKind(MediaItemKind kind) => switch (kind) {
  MediaItemKind.photo => 'Photo',
  MediaItemKind.video => 'Video',
  MediaItemKind.animation => 'GIF',
  _ => 'File',
};

String _clockDuration(Duration duration) {
  final seconds = duration.inSeconds;
  final minutes = seconds ~/ 60;
  final rest = (seconds % 60).toString().padLeft(2, '0');
  if (minutes < 60) return '$minutes:$rest';
  final hours = minutes ~/ 60;
  return '$hours:${(minutes % 60).toString().padLeft(2, '0')}:$rest';
}

String _englishSize(int bytes) => switch (bytes) {
  < 1024 => '$bytes B',
  < 1024 * 1024 => '${(bytes / 1024).toStringAsFixed(1)} KB',
  < 1024 * 1024 * 1024 => '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB',
  _ => '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB',
};

String _englishProgress(double? fraction) => switch (fraction) {
  final measured? => 'Downloading, ${(measured * 100).round()}%',
  null => 'Downloading',
};
