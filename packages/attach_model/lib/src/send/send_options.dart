import 'package:attach_model/src/item/attach_item.dart';
import 'package:content_model/content_model.dart';
import 'package:meta/meta.dart';

/// When a scheduled send goes out.
@immutable
sealed class SendSchedule {
  const SendSchedule._();

  /// At [time].
  const factory SendSchedule.at(DateTime time) = SendSchedule$At;

  /// When the recipient is next online.
  const factory SendSchedule.whenOnline() = SendSchedule$WhenOnline;
}

/// [SendSchedule.at].
final class SendSchedule$At extends SendSchedule {
  /// At [time].
  const SendSchedule$At(this.time) : super._();

  /// When the send goes out.
  final DateTime time;

  @override
  bool operator ==(Object other) =>
      other is SendSchedule$At && other.time == time;

  @override
  int get hashCode => Object.hash(SendSchedule$At, time);

  @override
  String toString() => 'SendSchedule.at($time)';
}

/// [SendSchedule.whenOnline].
final class SendSchedule$WhenOnline extends SendSchedule {
  /// When the recipient is next online.
  const SendSchedule$WhenOnline() : super._();

  @override
  bool operator ==(Object other) => other is SendSchedule$WhenOnline;

  @override
  int get hashCode => (SendSchedule$WhenOnline).hashCode;

  @override
  String toString() => 'SendSchedule.whenOnline()';
}

/// The **send options** of one send. Per-item options (spoiler, timer) are
/// on the attach items.
@immutable
final class SendOptions {
  /// Options; the defaults group media as media, at standard quality, with
  /// sound, now, the caption below.
  const SendOptions({
    this.grouped = true,
    this.asFiles = false,
    this.highQuality = false,
    this.silent = false,
    this.schedule,
    this.captionAbove = false,
    this.videoPreset,
  });

  /// Whether items that can share a send group do.
  final bool grouped;

  /// Whether photos, videos and animations go as files (originals, no
  /// preparation, grouped with files).
  final bool asFiles;

  /// Whether photos are prepared at the larger side limit.
  final bool highQuality;

  /// Whether the send notifies without sound.
  final bool silent;

  /// When the send goes out; null for now.
  final SendSchedule? schedule;

  /// Whether the caption is drawn above the media.
  final bool captionAbove;

  /// The chosen video preset, by its long side in pixels (as preparation
  /// names its presets); null for the platform's default.
  final int? videoPreset;

  /// A copy with the named fields replaced; [clearSchedule] and
  /// [clearVideoPreset] reset those to null.
  SendOptions copyWith({
    bool? grouped,
    bool? asFiles,
    bool? highQuality,
    bool? silent,
    SendSchedule? schedule,
    bool clearSchedule = false,
    bool? captionAbove,
    int? videoPreset,
    bool clearVideoPreset = false,
  }) => SendOptions(
    grouped: grouped ?? this.grouped,
    asFiles: asFiles ?? this.asFiles,
    highQuality: highQuality ?? this.highQuality,
    silent: silent ?? this.silent,
    schedule: clearSchedule ? null : schedule ?? this.schedule,
    captionAbove: captionAbove ?? this.captionAbove,
    videoPreset: clearVideoPreset ? null : videoPreset ?? this.videoPreset,
  );

  @override
  bool operator ==(Object other) =>
      other is SendOptions &&
      other.grouped == grouped &&
      other.asFiles == asFiles &&
      other.highQuality == highQuality &&
      other.silent == silent &&
      other.schedule == schedule &&
      other.captionAbove == captionAbove &&
      other.videoPreset == videoPreset;

  @override
  int get hashCode => Object.hash(
    grouped,
    asFiles,
    highQuality,
    silent,
    schedule,
    captionAbove,
    videoPreset,
  );

  @override
  String toString() =>
      'SendOptions(grouped: $grouped, asFiles: $asFiles, '
      'highQuality: $highQuality, silent: $silent, schedule: $schedule, '
      'captionAbove: $captionAbove, videoPreset: $videoPreset)';
}

/// What the user asked to send: the items in selection order, the batch
/// caption and the options.
@immutable
final class SendRequest {
  /// A request for [items] with [caption].
  SendRequest({
    required Iterable<AttachItem> items,
    required this.caption,
    this.options = const SendOptions(),
  }) : items = List.unmodifiable(items);

  /// The items, in selection order.
  final List<AttachItem> items;

  /// The batch caption; empty for none.
  final RichText caption;

  /// The send options.
  final SendOptions options;
}
