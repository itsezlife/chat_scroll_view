import 'package:content_model/content_model.dart';
import 'package:flutter/widgets.dart';
import 'package:message_media/src/chrome/media_options_affordance.dart';
import 'package:message_media/src/chrome/media_spoiler_cover.dart';
import 'package:message_media/src/chrome/media_spoiler_reveal.dart';
import 'package:message_media/src/chrome/media_time_pill.dart';
import 'package:message_media/src/layout/media_layout.dart';
import 'package:message_media/src/outgoing/media_sent_check.dart';
import 'package:message_media/src/policy/message_media_policy.dart';
import 'package:mpx_core/mpx_core.dart';

/// The cell a chrome slot is built for.
@immutable
final class MediaChromeData {
  /// The chrome of [cell], which draws [item].
  const MediaChromeData({
    required this.cell,
    required this.item,
    required this.family,
    this.downloadContext,
  });

  /// The cell: rect, fit, neighbours and corner radii.
  final MediaCell cell;

  /// The item the cell draws.
  final MediaItem item;

  /// The platform family of the policy that laid it out.
  final MessageMediaPlatform family;

  /// The class of conversation the media is shown in.
  final AutoDownloadContext? downloadContext;

  @override
  bool operator ==(Object other) =>
      other is MediaChromeData &&
      other.cell == cell &&
      other.item == item &&
      other.family == family &&
      other.downloadContext == downloadContext;

  @override
  int get hashCode => Object.hash(cell, item, family, downloadContext);
}

/// Builds a part of the cell's loading chrome (the info badge, the status
/// control) from the media's [state] and the [stock] part the asset view
/// would show: a slot keeps, wraps or replaces it.
typedef MediaLoadSlotBuilder =
    Widget Function(
      BuildContext context,
      MediaChromeData data,
      AssetLoadState state,
      Widget stock,
    );

/// What a spoiler slot draws over a cell whose item is behind a spoiler.
@immutable
final class MediaSpoilerData {
  /// The spoiler of [chrome]'s cell, revealed as far as [reveal] says.
  const MediaSpoilerData({
    required this.chrome,
    required this.reveal,
    required this.origin,
    required this.form,
  });

  /// The cell covered.
  final MediaChromeData chrome;

  /// The reveal's progress, curved: 0 hidden, 1 revealed.
  final Animation<double> reveal;

  /// Where the reveal starts, in the cell's coordinates (the touch point,
  /// or the cell's centre).
  final Offset origin;

  /// How the reveal uncovers the cell.
  final MediaSpoilerReveal form;
}

/// Builds the cover of a spoilered cell; it is the cell's size and is
/// removed once the reveal completes.
typedef MediaSpoilerBuilder =
    Widget Function(BuildContext context, MediaSpoilerData data);

/// What an options slot draws: the dots of one cell.
@immutable
final class MediaOptionsData {
  /// The affordance of [chrome]'s cell.
  const MediaOptionsData({required this.chrome, required this.affordance});

  /// The cell.
  final MediaChromeData chrome;

  /// The affordance, in the cell's coordinates.
  final MediaOptionsAffordance affordance;
}

/// Builds the options affordance; it is laid out in the affordance's icon
/// rect.
typedef MediaOptionsBuilder =
    Widget Function(BuildContext context, MediaOptionsData data);

/// The chrome a message media policy lays over its cells, each slot
/// replaceable on its own with a per-platform default.
///
/// | Slot | Default |
/// | --- | --- |
/// | [timePill] | host chrome; the rect is reported as `MediaLayout.timePill` |
/// | [infoBadge] | the loading stages' badge (duration, size, GIF label) |
/// | [statusControl] | the core's status control (download, cancel, play; an upload's ring and cancel) |
/// | [sentCheck] | [MediaSentCheck], while an item's upload is done and its message not yet published |
/// | [spoiler] | [MediaSpoilerCover]: a blurred copy under moving particles, revealed as [reveal] says |
/// | [optionsAffordance] | [MediaOptionsDots], where [options] places them |
///
/// The status control fades in with a spoiler's reveal and takes no taps
/// while the spoiler hides the item, since a tap there only reveals. The
/// sent check stands in the status control's place, faded with it; on a
/// message whose send failed neither shows (`MediaSendState.failed`).
@immutable
final class MediaChromeSlots {
  /// The given slots; each builder defaults to the package's own.
  const MediaChromeSlots({
    required this.timePill,
    required this.reveal,
    this.options = MediaOptionsPlacement.none,
    this.spoilerBlocksPinch = false,
    this.infoBadge = stockPart,
    this.statusControl = stockPart,
    this.sentCheck = MediaSentCheck.builder,
    this.spoiler = MediaSpoilerCover.builder,
    this.optionsAffordance = defaultOptions,
  });

  /// Android: the pill's rect bottom-right, a circle reveal from the touch
  /// point, the options dots on videos, animations and file rows.
  const MediaChromeSlots.android()
    : this(
        timePill: const MediaTimePillPlacement.android(),
        reveal: const MediaSpoilerReveal.circle(),
        options: const MediaOptionsPlacement.android(),
      );

  /// iOS: the pill's rect inset (6, 6), a spot reveal from the touch point,
  /// no pinch under a spoiler, no options dots.
  const MediaChromeSlots.ios()
    : this(
        timePill: const MediaTimePillPlacement.ios(),
        reveal: const MediaSpoilerReveal.spot(),
        spoilerBlocksPinch: true,
      );

  /// Desktop: the pill's rect inset 4, a cross-fade reveal, no options
  /// dots.
  const MediaChromeSlots.desktop()
    : this(
        timePill: const MediaTimePillPlacement.desktop(),
        reveal: const MediaSpoilerReveal.crossFade(),
      );

  /// The defaults of [family].
  factory MediaChromeSlots.of(MessageMediaPlatform family) => switch (family) {
    MessageMediaPlatform.android => const MediaChromeSlots.android(),
    MessageMediaPlatform.ios => const MediaChromeSlots.ios(),
    MessageMediaPlatform.desktop => const MediaChromeSlots.desktop(),
  };

  /// Where the time pill sits when the time is over the media.
  final MediaTimePillPlacement timePill;

  /// How a spoiler is revealed.
  final MediaSpoilerReveal reveal;

  /// Which cells carry the options affordance, and where.
  final MediaOptionsPlacement options;

  /// Whether a pinch on an item behind a spoiler is not the item's (it does
  /// not zoom it): the gestures read it.
  final bool spoilerBlocksPinch;

  /// Builds the info badge.
  final MediaLoadSlotBuilder infoBadge;

  /// Builds the status control (downloads, and an outgoing item's
  /// upload).
  final MediaLoadSlotBuilder statusControl;

  /// Builds the per-item sent check, given the stock control (which shows
  /// nothing for a sent upload).
  final MediaLoadSlotBuilder sentCheck;

  /// Builds a spoiler's cover.
  final MediaSpoilerBuilder spoiler;

  /// Builds the options affordance.
  final MediaOptionsBuilder optionsAffordance;

  /// The [MediaLoadSlotBuilder] that keeps the stock part.
  static Widget stockPart(
    BuildContext context,
    MediaChromeData data,
    AssetLoadState state,
    Widget stock,
  ) => stock;

  /// The default [MediaOptionsBuilder]: [MediaOptionsDots].
  static Widget defaultOptions(BuildContext context, MediaOptionsData data) =>
      const MediaOptionsDots();

  /// Whether [item] is behind a spoiler its cell draws: a box (photo, video,
  /// animation) marked so. A file row has no picture to cover.
  static bool coversSpoiler(MediaItem item, MediaCell cell) =>
      item.spoiler && cell.kind.isPicture;

  /// The `spoiler` hit part's rect of [cell] (layout coordinates): the
  /// cell's rect while its item's spoiler is hidden, null otherwise.
  static Rect? spoilerRectOf(
    MediaCell cell,
    MediaItem item, {
    required bool revealed,
  }) => coversSpoiler(item, cell) && !revealed ? cell.rect : null;

  /// A copy with the given slots replaced.
  MediaChromeSlots copyWith({
    MediaTimePillPlacement? timePill,
    MediaSpoilerReveal? reveal,
    MediaOptionsPlacement? options,
    bool? spoilerBlocksPinch,
    MediaLoadSlotBuilder? infoBadge,
    MediaLoadSlotBuilder? statusControl,
    MediaLoadSlotBuilder? sentCheck,
    MediaSpoilerBuilder? spoiler,
    MediaOptionsBuilder? optionsAffordance,
  }) => MediaChromeSlots(
    timePill: timePill ?? this.timePill,
    reveal: reveal ?? this.reveal,
    options: options ?? this.options,
    spoilerBlocksPinch: spoilerBlocksPinch ?? this.spoilerBlocksPinch,
    infoBadge: infoBadge ?? this.infoBadge,
    statusControl: statusControl ?? this.statusControl,
    sentCheck: sentCheck ?? this.sentCheck,
    spoiler: spoiler ?? this.spoiler,
    optionsAffordance: optionsAffordance ?? this.optionsAffordance,
  );

  @override
  bool operator ==(Object other) =>
      other is MediaChromeSlots &&
      other.timePill == timePill &&
      other.reveal == reveal &&
      other.options == options &&
      other.spoilerBlocksPinch == spoilerBlocksPinch &&
      other.infoBadge == infoBadge &&
      other.statusControl == statusControl &&
      other.sentCheck == sentCheck &&
      other.spoiler == spoiler &&
      other.optionsAffordance == optionsAffordance;

  @override
  int get hashCode => Object.hash(
    timePill,
    reveal,
    options,
    spoilerBlocksPinch,
    infoBadge,
    statusControl,
    sentCheck,
    spoiler,
    optionsAffordance,
  );
}
