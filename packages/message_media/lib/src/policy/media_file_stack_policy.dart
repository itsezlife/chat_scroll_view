import 'dart:math' as math;

import 'package:chrome_foundation/chrome_foundation.dart' show MediaStrings;
import 'package:content_model/content_model.dart';
import 'package:flutter/painting.dart';
import 'package:message_media/src/layout/media_corner_radii.dart';
import 'package:message_media/src/layout/media_file_row.dart';
import 'package:message_media/src/layout/media_layout.dart';
import 'package:message_media/src/layout/media_layout_input.dart';
import 'package:message_media/src/layout/media_layout_text.dart';
import 'package:message_media/src/policy/media_file_text.dart';
import 'package:meta/meta.dart';

// --- Row metrics ---

/// Where a row's name and info line sit vertically.
enum MediaFileTextPlacement {
  /// At the metrics' fixed name and info tops.
  fixed,

  /// The name and the info line together, centred on the leading control
  /// or thumbnail, the info line right under the name.
  centredOnLeading,
}

/// The geometry of one kind of file row: its height, its leading control
/// or thumbnail, and where its text starts.
///
/// Horizontal values count from the bubble body's left edge (a row spans the
/// bubble); vertical values from the row's own top. The bubble's vertical
/// padding around the media is the host bubble's.
@immutable
final class MediaFileRowMetrics {
  /// Metrics of the given values.
  const MediaFileRowMetrics({
    required this.height,
    required this.leading,
    required this.textLeft,
    required this.trailingPadding,
    this.nameTop = 0,
    this.infoTop = 0,
    this.linkTop,
    this.extraNameLineHeight = 0,
    this.heightGrowsWithNameLines = false,
    this.placement = MediaFileTextPlacement.fixed,
    this.infoGap = 0,
  });

  /// The row's height with a one-line name.
  final double height;

  /// The status control's rect, or the thumbnail's in a thumbnail row.
  final Rect leading;

  /// Where the name and info line start.
  final double textLeft;

  /// Room kept right of the text: the text wraps at
  /// `width − textLeft − trailingPadding`, and a bubble that widens to its
  /// text widens to `textLeft + text + trailingPadding`.
  final double trailingPadding;

  /// The name's top ([MediaFileTextPlacement.fixed]).
  final double nameTop;

  /// The info line's top under a one-line name ([MediaFileTextPlacement.fixed]).
  final double infoTop;

  /// The link line's top under a one-line name; null when the row draws no
  /// link line.
  final double? linkTop;

  /// How much each name line past the first moves the info and link lines
  /// down.
  final double extraNameLineHeight;

  /// Whether the row also grows by [extraNameLineHeight] per extra name
  /// line (a thumbnail row keeps the thumbnail's height).
  final bool heightGrowsWithNameLines;

  /// How the name and info line are placed.
  final MediaFileTextPlacement placement;

  /// The gap between the name and the info line when they are centred
  /// (negative overlaps the line boxes).
  final double infoGap;

  /// A copy with the given values replaced.
  MediaFileRowMetrics copyWith({
    double? height,
    Rect? leading,
    double? textLeft,
    double? trailingPadding,
    double? nameTop,
    double? infoTop,
    double? linkTop,
    double? extraNameLineHeight,
    bool? heightGrowsWithNameLines,
    MediaFileTextPlacement? placement,
    double? infoGap,
  }) => MediaFileRowMetrics(
    height: height ?? this.height,
    leading: leading ?? this.leading,
    textLeft: textLeft ?? this.textLeft,
    trailingPadding: trailingPadding ?? this.trailingPadding,
    nameTop: nameTop ?? this.nameTop,
    infoTop: infoTop ?? this.infoTop,
    linkTop: linkTop ?? this.linkTop,
    extraNameLineHeight: extraNameLineHeight ?? this.extraNameLineHeight,
    heightGrowsWithNameLines:
        heightGrowsWithNameLines ?? this.heightGrowsWithNameLines,
    placement: placement ?? this.placement,
    infoGap: infoGap ?? this.infoGap,
  );

  @override
  bool operator ==(Object other) =>
      other is MediaFileRowMetrics &&
      other.height == height &&
      other.leading == leading &&
      other.textLeft == textLeft &&
      other.trailingPadding == trailingPadding &&
      other.nameTop == nameTop &&
      other.infoTop == infoTop &&
      other.linkTop == linkTop &&
      other.extraNameLineHeight == extraNameLineHeight &&
      other.heightGrowsWithNameLines == heightGrowsWithNameLines &&
      other.placement == placement &&
      other.infoGap == infoGap;

  @override
  int get hashCode => Object.hash(
    height,
    leading,
    textLeft,
    trailingPadding,
    nameTop,
    infoTop,
    linkTop,
    extraNameLineHeight,
    heightGrowsWithNameLines,
    placement,
    infoGap,
  );
}

// --- Thumbnail corners ---

/// How a file row's thumbnail is rounded.
@immutable
sealed class MediaFileThumbCorners {
  const MediaFileThumbCorners._();

  /// The leading (left) corners follow the row cell's own radii, the
  /// trailing ones take [trailing].
  const factory MediaFileThumbCorners.leadingFromCell({double trailing}) =
      MediaFileThumbCorners$LeadingFromCell;

  /// Every corner [radius].
  const factory MediaFileThumbCorners.uniform(double radius) =
      MediaFileThumbCorners$Uniform;

  /// A corner at the bubble's outer corner (both of the cell's sides there
  /// on the bubble's edge) takes [large], every other [small].
  const factory MediaFileThumbCorners.byPosition({double small, double large}) =
      MediaFileThumbCorners$ByPosition;

  /// The thumbnail's radii in a cell rounded [cell] whose sides touch
  /// [neighbours] (both physical, before any mirroring).
  MediaCornerRadii radiiOf(MediaCornerRadii cell, MediaNeighbours neighbours);
}

/// [MediaFileThumbCorners.leadingFromCell].
final class MediaFileThumbCorners$LeadingFromCell
    extends MediaFileThumbCorners {
  /// Leading corners from the cell, trailing [trailing].
  const MediaFileThumbCorners$LeadingFromCell({this.trailing = 4}) : super._();

  /// The trailing corners' radius.
  final double trailing;

  @override
  MediaCornerRadii radiiOf(MediaCornerRadii cell, MediaNeighbours neighbours) =>
      MediaCornerRadii(
        topLeft: cell.topLeft,
        topRight: trailing,
        bottomRight: trailing,
        bottomLeft: cell.bottomLeft,
      );

  @override
  bool operator ==(Object other) =>
      other is MediaFileThumbCorners$LeadingFromCell &&
      other.trailing == trailing;

  @override
  int get hashCode =>
      Object.hash(MediaFileThumbCorners$LeadingFromCell, trailing);
}

/// [MediaFileThumbCorners.uniform].
final class MediaFileThumbCorners$Uniform extends MediaFileThumbCorners {
  /// Every corner [radius].
  const MediaFileThumbCorners$Uniform(this.radius) : super._();

  /// The radius.
  final double radius;

  @override
  MediaCornerRadii radiiOf(MediaCornerRadii cell, MediaNeighbours neighbours) =>
      MediaCornerRadii.all(radius);

  @override
  bool operator ==(Object other) =>
      other is MediaFileThumbCorners$Uniform && other.radius == radius;

  @override
  int get hashCode => Object.hash(MediaFileThumbCorners$Uniform, radius);
}

/// [MediaFileThumbCorners.byPosition].
final class MediaFileThumbCorners$ByPosition extends MediaFileThumbCorners {
  /// Small inside, large at the bubble's corners.
  const MediaFileThumbCorners$ByPosition({this.small = 4, this.large = 12})
    : super._();

  /// Inner corners.
  final double small;

  /// Corners at the bubble's outer corner.
  final double large;

  @override
  MediaCornerRadii radiiOf(MediaCornerRadii cell, MediaNeighbours neighbours) {
    double of(MediaNeighbour a, MediaNeighbour b) =>
        a == MediaNeighbour.bubbleEdge && b == MediaNeighbour.bubbleEdge
        ? large
        : small;
    return MediaCornerRadii(
      topLeft: of(neighbours.top, neighbours.left),
      topRight: of(neighbours.top, neighbours.right),
      bottomRight: of(neighbours.bottom, neighbours.right),
      bottomLeft: of(neighbours.bottom, neighbours.left),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MediaFileThumbCorners$ByPosition &&
      other.small == small &&
      other.large == large;

  @override
  int get hashCode =>
      Object.hash(MediaFileThumbCorners$ByPosition, small, large);
}

// --- Stack width ---

/// How wide a file stack's bubble is.
@immutable
sealed class MediaFileStackWidth {
  const MediaFileStackWidth._();

  /// The Android rule: a single file takes the max text width, widened to
  /// its text and caption; a stack `min(listWidth − 50 − avatar, 300)`;
  /// neither past the bubble's max content width.
  const factory MediaFileStackWidth.android({
    double stackInset,
    double avatarInset,
    double sideButtonInset,
    double stackMaxWidth,
    double captionPadding,
  }) = MediaFileStackWidth$Android;

  /// The iOS rule: the rows' text and control area, up to the bubble's max
  /// content width.
  const factory MediaFileStackWidth.ios() = MediaFileStackWidth$IOS;

  /// The desktop rule: the rows' content between [minWidth] and [maxWidth].
  const factory MediaFileStackWidth.desktop({
    double minWidth,
    double maxWidth,
  }) = MediaFileStackWidth$Desktop;

  /// The stack's width for [input], given the widest row's need [need]
  /// (`textLeft + text + trailingPadding`); [single] for one file.
  double widthOf(
    MediaLayoutInput input, {
    required bool single,
    required double need,
  });
}

/// [MediaFileStackWidth.android].
///
/// | Field | Value | Role |
/// | --- | --- | --- |
/// | [stackInset] | 50 | Taken from the list width for a stack |
/// | [avatarInset] | 52 | More taken beside an avatar |
/// | [sideButtonInset] | 20 | More taken with a side button |
/// | [stackMaxWidth] | 300 | A stack's cap |
/// | [captionPadding] | 31 | A single file widens to its caption + this |
final class MediaFileStackWidth$Android extends MediaFileStackWidth {
  /// The Android values.
  const MediaFileStackWidth$Android({
    this.stackInset = 50,
    this.avatarInset = 52,
    this.sideButtonInset = 20,
    this.stackMaxWidth = 300,
    this.captionPadding = 31,
  }) : super._();

  /// See the class table.
  final double stackInset;

  /// See the class table.
  final double avatarInset;

  /// See the class table.
  final double sideButtonInset;

  /// See the class table.
  final double stackMaxWidth;

  /// See the class table.
  final double captionPadding;

  @override
  double widthOf(
    MediaLayoutInput input, {
    required bool single,
    required double need,
  }) {
    // The bubble cannot be wider than its max content width: a row past it
    // would draw outside the bubble, its options with it.
    final most = math.min(input.availableWidth, input.contentWidth);
    if (!single) {
      final room =
          input.availableWidth -
          stackInset -
          (input.showsAvatar ? avatarInset : 0) -
          (input.hasSideButton ? sideButtonInset : 0);
      return math.max(0, math.min(math.min(room, stackMaxWidth), most));
    }
    final caption = switch (input.captionWidth) {
      final width? => width + captionPadding,
      null => 0.0,
    };
    return math.min(
      most,
      math.max(input.contentWidth, math.max(need, caption)),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MediaFileStackWidth$Android &&
      other.stackInset == stackInset &&
      other.avatarInset == avatarInset &&
      other.sideButtonInset == sideButtonInset &&
      other.stackMaxWidth == stackMaxWidth &&
      other.captionPadding == captionPadding;

  @override
  int get hashCode => Object.hash(
    MediaFileStackWidth$Android,
    stackInset,
    avatarInset,
    sideButtonInset,
    stackMaxWidth,
    captionPadding,
  );
}

/// [MediaFileStackWidth.ios].
final class MediaFileStackWidth$IOS extends MediaFileStackWidth {
  /// The iOS rule.
  const MediaFileStackWidth$IOS() : super._();

  @override
  double widthOf(
    MediaLayoutInput input, {
    required bool single,
    required double need,
  }) => math.min(input.contentWidth, need);

  @override
  bool operator ==(Object other) => other is MediaFileStackWidth$IOS;

  @override
  int get hashCode => (MediaFileStackWidth$IOS).hashCode;
}

/// [MediaFileStackWidth.desktop]: [minWidth] 268, [maxWidth] 430.
final class MediaFileStackWidth$Desktop extends MediaFileStackWidth {
  /// The desktop values.
  const MediaFileStackWidth$Desktop({this.minWidth = 268, this.maxWidth = 430})
    : super._();

  /// The narrowest file bubble.
  final double minWidth;

  /// The widest file bubble.
  final double maxWidth;

  @override
  double widthOf(
    MediaLayoutInput input, {
    required bool single,
    required double need,
  }) {
    final most = math.min(maxWidth, input.contentWidth);
    return need.clamp(math.min(minWidth, most), most);
  }

  @override
  bool operator ==(Object other) =>
      other is MediaFileStackWidth$Desktop &&
      other.minWidth == minWidth &&
      other.maxWidth == maxWidth;

  @override
  int get hashCode =>
      Object.hash(MediaFileStackWidth$Desktop, minWidth, maxWidth);
}

// --- Time ---

/// How the last file row grows to fit the message's time (the time sits on
/// the last file when nothing follows it).
///
/// When the time does not fit beside the info line (`width − reserve −
/// infoWidth < timeWidth`) the row grows by [wrapGrowth]; when it does, by
/// [inlineGrowth]. Rows with a thumbnail keep their height.
@immutable
final class MediaFileTimeGrowth {
  /// Growth of the given values.
  const MediaFileTimeGrowth({
    this.reserve = 122,
    this.wrapGrowth = 12,
    this.inlineGrowth = 4,
  });

  /// The row width the control, text inset and paddings take.
  final double reserve;

  /// Growth when the time takes a line of its own.
  final double wrapGrowth;

  /// Growth when the time fits beside the info line.
  final double inlineGrowth;

  /// The growth of a row [width] wide with an info line [infoWidth] wide and
  /// a time [timeWidth] wide.
  double growthOf({
    required double width,
    required double infoWidth,
    required double timeWidth,
  }) => width - reserve - infoWidth < timeWidth ? wrapGrowth : inlineGrowth;

  @override
  bool operator ==(Object other) =>
      other is MediaFileTimeGrowth &&
      other.reserve == reserve &&
      other.wrapGrowth == wrapGrowth &&
      other.inlineGrowth == inlineGrowth;

  @override
  int get hashCode => Object.hash(reserve, wrapGrowth, inlineGrowth);
}

// --- Policy ---

/// How a platform lays files out: one row per file in a vertical stack,
/// never in a mosaic, each row with its own caption slot.
///
/// | Part | Android | iOS | Desktop |
/// | --- | --- | --- | --- |
/// | [width] | single: max text width, widened; stack: `min(list − 50 − avatar, 300)`; both ≤ content width | text + control area, ≤ content width | 268 to 430 |
/// | [plain] | 56 high, 44 control at (14, 6), text at 67, name + 4, info + 27 | 65 high (insets 15, 9, 15, 12), 44 control at (18, 9), text at 70, centred | 60 high, padding (12, 8, 10, 8), 44 thumb, skip 11, name 12, status 34 |
/// | [thumbnail] | 86 thumb at (4, 0), text at 100, name 8, info under it + 13 | 74 thumb at (14, 2), control area 86 | 84 high, padding (6, 6, 10, 6), 72 thumb, skip 14, name 11, status 31, link 55 |
/// | [groupedPlain] / [groupedThumbnail] | as alone | as alone | padding (12, 5, 10, 5) / (6, 3, 10, 3), name 9 / 8, status 31 / 28, link 52 |
/// | Name | 15, 2 lines, middle ellipsis, + 16 per extra line | 16, 1 line (2 with a thumbnail) | 13 semibold, 1 line, tooltip when elided |
/// | Info | `"<size> <EXT>"`, 12 | size, 13, monospaced digits | size, 12 |
/// | [thumbCorners] | leading from the cell, trailing 4 | 8 | 4 small / 12 large |
/// | Stack | non-top rows pull up 3 (thumbnail) / 6, non-bottom rows trimmed the same | rows overlap 4 | rows pull up 6, an extra footer line |
/// | Time | last row + 12 or + 4 | — | — |
/// | RTL | not mirrored | not mirrored | mirrored |
///
/// A file has a thumbnail when its mime type is `image/*` or `video/mp4`, or
/// its descriptor carries one ([hasThumbnail]).
@immutable
final class MediaFileStackPolicy {
  /// A policy of the given parts.
  const MediaFileStackPolicy({
    required this.width,
    required this.plain,
    required this.thumbnail,
    required this.text,
    required this.thumbCorners,
    this.groupedPlain,
    this.groupedThumbnail,
    this.controlExtent = 44,
    this.nameMaxLines = 1,
    this.nameMaxLinesWithThumbnail = 1,
    this.pullUp = 0,
    this.pullUpWithThumbnail = 0,
    this.trimBelow = 0,
    this.trimBelowWithThumbnail = 0,
    this.timeGrowth,
    this.footerLineHeight = 0,
    this.infoShowsExtension = false,
    this.tooltipWhenElided = false,
    this.mirrorsInRtl = false,
  });

  /// The Android family's file rows.
  const MediaFileStackPolicy.android()
    : this(
        width: const MediaFileStackWidth.android(),
        plain: const MediaFileRowMetrics(
          height: 56,
          leading: Rect.fromLTWH(14, 6, 44, 44),
          textLeft: 67,
          trailingPadding: 41,
          nameTop: 10,
          infoTop: 33,
          extraNameLineHeight: 16,
          heightGrowsWithNameLines: true,
        ),
        thumbnail: const MediaFileRowMetrics(
          height: 86,
          leading: Rect.fromLTWH(4, 0, 86, 86),
          textLeft: 100,
          trailingPadding: 38,
          nameTop: 8,
          infoTop: 37,
          extraNameLineHeight: 16,
        ),
        text: const MediaFileText(nameSize: 15, infoSize: 12),
        thumbCorners: const MediaFileThumbCorners.leadingFromCell(),
        nameMaxLines: 2,
        nameMaxLinesWithThumbnail: 2,
        pullUp: 6,
        pullUpWithThumbnail: 3,
        trimBelow: 6,
        trimBelowWithThumbnail: 3,
        timeGrowth: const MediaFileTimeGrowth(),
        infoShowsExtension: true,
      );

  /// The iOS family's file rows.
  const MediaFileStackPolicy.ios()
    : this(
        width: const MediaFileStackWidth.ios(),
        plain: const MediaFileRowMetrics(
          height: 65,
          leading: Rect.fromLTWH(18, 9, 44, 44),
          textLeft: 70,
          trailingPadding: 15,
          placement: MediaFileTextPlacement.centredOnLeading,
          infoGap: -1,
        ),
        thumbnail: const MediaFileRowMetrics(
          height: 95,
          leading: Rect.fromLTWH(14, 2, 74, 74),
          textLeft: 101,
          trailingPadding: 15,
          placement: MediaFileTextPlacement.centredOnLeading,
          infoGap: -1,
        ),
        text: const MediaFileText(
          nameSize: 16,
          infoSize: 13,
          tabularDigits: true,
        ),
        thumbCorners: const MediaFileThumbCorners.uniform(8),
        nameMaxLinesWithThumbnail: 2,
        pullUp: 4,
        pullUpWithThumbnail: 4,
      );

  /// The desktop family's file rows.
  const MediaFileStackPolicy.desktop()
    : this(
        width: const MediaFileStackWidth.desktop(),
        plain: const MediaFileRowMetrics(
          height: 60,
          leading: Rect.fromLTWH(12, 8, 44, 44),
          textLeft: 67,
          trailingPadding: 10,
          nameTop: 12,
          infoTop: 34,
        ),
        thumbnail: const MediaFileRowMetrics(
          height: 84,
          leading: Rect.fromLTWH(6, 6, 72, 72),
          textLeft: 92,
          trailingPadding: 10,
          nameTop: 11,
          infoTop: 31,
          linkTop: 55,
        ),
        groupedPlain: const MediaFileRowMetrics(
          height: 54,
          leading: Rect.fromLTWH(12, 5, 44, 44),
          textLeft: 67,
          trailingPadding: 10,
          nameTop: 9,
          infoTop: 31,
        ),
        groupedThumbnail: const MediaFileRowMetrics(
          height: 78,
          leading: Rect.fromLTWH(6, 3, 72, 72),
          textLeft: 92,
          trailingPadding: 10,
          nameTop: 8,
          infoTop: 28,
          linkTop: 52,
        ),
        text: const MediaFileText(
          nameSize: 13,
          nameWeight: FontWeight.w600,
          infoSize: 12,
        ),
        thumbCorners: const MediaFileThumbCorners.byPosition(),
        pullUp: 6,
        pullUpWithThumbnail: 6,
        footerLineHeight: 13,
        tooltipWhenElided: true,
        mirrorsInRtl: true,
      );

  /// The bubble's width rule.
  final MediaFileStackWidth width;

  /// A row without a thumbnail.
  final MediaFileRowMetrics plain;

  /// A row with a thumbnail.
  final MediaFileRowMetrics thumbnail;

  /// A row without a thumbnail in a stack of two or more; null is [plain].
  final MediaFileRowMetrics? groupedPlain;

  /// A row with a thumbnail in a stack of two or more; null is [thumbnail].
  final MediaFileRowMetrics? groupedThumbnail;

  /// The status control's side.
  final double controlExtent;

  /// The name's lines in a row without a thumbnail.
  final int nameMaxLines;

  /// The name's lines in a row with a thumbnail.
  final int nameMaxLinesWithThumbnail;

  /// How far a row below the first moves up over the row above it (no
  /// thumbnail / thumbnail).
  final double pullUp;

  /// See [pullUp].
  final double pullUpWithThumbnail;

  /// How much a row above the last gives up at its bottom (no thumbnail /
  /// thumbnail); with [pullUp] it is the overlap between two rows.
  final double trimBelow;

  /// See [trimBelow].
  final double trimBelowWithThumbnail;

  /// The last row's growth for the time; null when the row keeps its
  /// height.
  final MediaFileTimeGrowth? timeGrowth;

  /// The extra line under a stack of two or more for views, signature or
  /// the edited mark (`MediaLayoutChrome.hasFooterInfo`); 0 for none.
  final double footerLineHeight;

  /// Whether the info line shows the extension after the size.
  final bool infoShowsExtension;

  /// Whether an elided name shows the full name in a tooltip.
  final bool tooltipWhenElided;

  /// Whether rows are mirrored in a right-to-left list.
  final bool mirrorsInRtl;

  /// The name and info line's type.
  final MediaFileText text;

  /// The thumbnail's corners.
  final MediaFileThumbCorners thumbCorners;

  /// Whether [item] draws a thumbnail: an `image/*` or `video/mp4` file, or
  /// one whose descriptor carries a thumbnail.
  static bool hasThumbnail(MediaItem item) {
    final descriptor = item.descriptor;
    return descriptor.thumbnail != null ||
        (descriptor.mimeType?.startsWith('image/') ?? false) ||
        descriptor.mimeType == 'video/mp4';
  }

  /// The upper-case extension of [fileName], or null when it has none.
  static String? extensionOf(String? fileName) {
    if (fileName == null) return null;
    final dot = fileName.lastIndexOf('.');
    if (dot <= 0 || dot == fileName.length - 1) return null;
    return fileName.substring(dot + 1).toUpperCase();
  }

  /// [item]'s info line at rest, worded by the host's [strings].
  String infoTextOf(MediaItem item, MediaStrings strings) =>
      strings.fileInfo(switch (item.descriptor.byteSize) {
        final bytes? => strings.size(bytes),
        null => null,
      }, infoShowsExtension ? extensionOf(item.descriptor.fileName) : null);

  /// The metrics of a row with or without a thumbnail, alone or [grouped].
  MediaFileRowMetrics metricsOf({
    required bool thumbnail,
    required bool grouped,
  }) => switch ((thumbnail, grouped)) {
    (true, true) => groupedThumbnail ?? this.thumbnail,
    (true, false) => this.thumbnail,
    (false, true) => groupedPlain ?? plain,
    (false, false) => plain,
  };

  /// Lays [items] out as one stack whose top is at [top], its outer top and
  /// bottom sides touching [topSide] and [bottomSide]; [isLastBlock] when
  /// nothing follows it in the layout (the time may sit on its last row).
  MediaBlock$FileStack layout(
    List<MediaItem> items,
    MediaLayoutInput input, {
    required double top,
    required MediaNeighbour topSide,
    required MediaNeighbour bottomSide,
    required bool isLastBlock,
  }) {
    final grouped = items.length > 1;
    final type = input.text;
    final nameStyle = text.nameOver(type.style);
    final infoStyle = text.infoOver(type.style);
    final prepared = [
      for (final item in items)
        (
          item: item,
          thumbnail: hasThumbnail(item),
          name: item.descriptor.fileName ?? '',
          info: infoTextOf(item, type.strings),
        ),
    ];
    var need = 0.0;
    for (final row in prepared) {
      final metrics = metricsOf(thumbnail: row.thumbnail, grouped: grouped);
      final name = type.measureOf(TextSpan(text: row.name, style: nameStyle));
      final info = type.measureOf(TextSpan(text: row.info, style: infoStyle));
      need = math.max(
        need,
        metrics.textLeft +
            math.max(name.width, info.width) +
            metrics.trailingPadding,
      );
    }
    final stackWidth = width.widthOf(input, single: !grouped, need: need);

    final cells = <MediaCell>[];
    final rows = <MediaFileRow>[];
    var y = top;
    final last = items.length - 1;
    for (final (index, row) in prepared.indexed) {
      final metrics = metricsOf(thumbnail: row.thumbnail, grouped: grouped);
      // Rows meet each other; a row under the caption of the row above
      // starts at the caption's bottom.
      if (index > 0 &&
          !input.fileCaptionHeights.containsKey(prepared[index - 1].item.id)) {
        y -=
            (row.thumbnail ? pullUpWithThumbnail : pullUp) +
            (prepared[index - 1].thumbnail
                ? trimBelowWithThumbnail
                : trimBelow);
      }
      final textWidth = math.max<double>(
        0,
        stackWidth - metrics.textLeft - metrics.trailingPadding,
      );
      final name = type.measureOf(
        TextSpan(text: row.name, style: nameStyle),
        maxWidth: textWidth,
        maxLines: row.thumbnail ? nameMaxLinesWithThumbnail : nameMaxLines,
      );
      final info = type.measureOf(TextSpan(text: row.info, style: infoStyle));
      final extra = (name.lines - 1) * metrics.extraNameLineHeight;
      final ownCaption = input.fileCaptionHeights[row.item.id];
      final captionBelow =
          ownCaption != null ||
          (index == last &&
              input.captionPosition == MediaCaptionPosition.below);
      final carriesTime = index == last && isLastBlock && !captionBelow;
      var height =
          metrics.height + (metrics.heightGrowsWithNameLines ? extra : 0);
      if (timeGrowth case final growth? when carriesTime && !row.thumbnail) {
        height += growth.growthOf(
          width: stackWidth,
          infoWidth: info.width,
          timeWidth: input.chrome.timeWidth,
        );
      }
      final (nameRect, infoRect) = switch (metrics.placement) {
        MediaFileTextPlacement.fixed => (
          Rect.fromLTWH(
            metrics.textLeft,
            metrics.nameTop,
            textWidth,
            name.height,
          ),
          Rect.fromLTWH(
            metrics.textLeft,
            metrics.infoTop + extra,
            textWidth,
            info.height,
          ),
        ),
        MediaFileTextPlacement.centredOnLeading => _centred(
          metrics,
          textWidth,
          name,
          info,
        ),
      };
      final rect = Rect.fromLTWH(0, y, stackWidth, height);
      cells.add(
        MediaCell(
          itemId: row.item.id,
          kind: row.item.kind,
          rect: rect,
          neighbours: MediaNeighbours(
            top: index == 0 ? topSide : MediaNeighbour.item,
            bottom: index == last ? bottomSide : MediaNeighbour.item,
            left: MediaNeighbour.bubbleEdge,
            right: MediaNeighbour.bubbleEdge,
          ),
        ),
      );
      y = rect.bottom;
      Rect? captionSlot;
      if (ownCaption case final captionHeight?) {
        captionSlot = Rect.fromLTWH(0, y, stackWidth, captionHeight);
        y += captionHeight;
      }
      rows.add(
        MediaFileRow(
          itemId: row.item.id,
          hasThumbnail: row.thumbnail,
          leading: metrics.leading,
          control: row.thumbnail
              ? Rect.fromCenter(
                  center: metrics.leading.center,
                  width: controlExtent,
                  height: controlExtent,
                )
              : metrics.leading,
          name: nameRect,
          nameLines: name.lines,
          info: infoRect,
          infoText: row.info,
          link: switch (metrics.linkTop) {
            final linkTop? when row.thumbnail => Rect.fromLTWH(
              metrics.textLeft,
              linkTop + extra,
              textWidth,
              info.height,
            ),
            _ => null,
          },
          captionSlot: captionSlot,
          carriesTime: carriesTime,
          mirrorsInRtl: mirrorsInRtl,
        ),
      );
    }
    Rect? footer;
    final lastCaptionBelow =
        input.fileCaptionHeights.containsKey(items[last].id) ||
        input.captionPosition == MediaCaptionPosition.below;
    if (grouped &&
        isLastBlock &&
        footerLineHeight > 0 &&
        input.chrome.hasFooterInfo &&
        !lastCaptionBelow) {
      footer = Rect.fromLTWH(0, y, stackWidth, footerLineHeight);
      y += footerLineHeight;
    }
    return MediaBlock$FileStack(
      rect: Rect.fromLTWH(0, top, stackWidth, y - top),
      cells: cells,
      rows: rows,
      footer: footer,
    );
  }

  static (Rect, Rect) _centred(
    MediaFileRowMetrics metrics,
    double textWidth,
    MediaTextSize name,
    MediaTextSize info,
  ) {
    final nameTop =
        metrics.leading.center.dy -
        (name.height + metrics.infoGap + info.height) / 2;
    return (
      Rect.fromLTWH(metrics.textLeft, nameTop, textWidth, name.height),
      Rect.fromLTWH(
        metrics.textLeft,
        nameTop + name.height + metrics.infoGap,
        textWidth,
        info.height,
      ),
    );
  }

  /// A copy with the given parts replaced.
  MediaFileStackPolicy copyWith({
    MediaFileStackWidth? width,
    MediaFileRowMetrics? plain,
    MediaFileRowMetrics? thumbnail,
    MediaFileRowMetrics? groupedPlain,
    MediaFileRowMetrics? groupedThumbnail,
    double? controlExtent,
    int? nameMaxLines,
    int? nameMaxLinesWithThumbnail,
    double? pullUp,
    double? pullUpWithThumbnail,
    double? trimBelow,
    double? trimBelowWithThumbnail,
    MediaFileTimeGrowth? timeGrowth,
    double? footerLineHeight,
    bool? infoShowsExtension,
    bool? tooltipWhenElided,
    bool? mirrorsInRtl,
    MediaFileText? text,
    MediaFileThumbCorners? thumbCorners,
  }) => MediaFileStackPolicy(
    width: width ?? this.width,
    plain: plain ?? this.plain,
    thumbnail: thumbnail ?? this.thumbnail,
    groupedPlain: groupedPlain ?? this.groupedPlain,
    groupedThumbnail: groupedThumbnail ?? this.groupedThumbnail,
    controlExtent: controlExtent ?? this.controlExtent,
    nameMaxLines: nameMaxLines ?? this.nameMaxLines,
    nameMaxLinesWithThumbnail:
        nameMaxLinesWithThumbnail ?? this.nameMaxLinesWithThumbnail,
    pullUp: pullUp ?? this.pullUp,
    pullUpWithThumbnail: pullUpWithThumbnail ?? this.pullUpWithThumbnail,
    trimBelow: trimBelow ?? this.trimBelow,
    trimBelowWithThumbnail:
        trimBelowWithThumbnail ?? this.trimBelowWithThumbnail,
    timeGrowth: timeGrowth ?? this.timeGrowth,
    footerLineHeight: footerLineHeight ?? this.footerLineHeight,
    infoShowsExtension: infoShowsExtension ?? this.infoShowsExtension,
    tooltipWhenElided: tooltipWhenElided ?? this.tooltipWhenElided,
    mirrorsInRtl: mirrorsInRtl ?? this.mirrorsInRtl,
    text: text ?? this.text,
    thumbCorners: thumbCorners ?? this.thumbCorners,
  );

  @override
  bool operator ==(Object other) =>
      other is MediaFileStackPolicy &&
      other.width == width &&
      other.plain == plain &&
      other.thumbnail == thumbnail &&
      other.groupedPlain == groupedPlain &&
      other.groupedThumbnail == groupedThumbnail &&
      other.controlExtent == controlExtent &&
      other.nameMaxLines == nameMaxLines &&
      other.nameMaxLinesWithThumbnail == nameMaxLinesWithThumbnail &&
      other.pullUp == pullUp &&
      other.pullUpWithThumbnail == pullUpWithThumbnail &&
      other.trimBelow == trimBelow &&
      other.trimBelowWithThumbnail == trimBelowWithThumbnail &&
      other.timeGrowth == timeGrowth &&
      other.footerLineHeight == footerLineHeight &&
      other.infoShowsExtension == infoShowsExtension &&
      other.tooltipWhenElided == tooltipWhenElided &&
      other.mirrorsInRtl == mirrorsInRtl &&
      other.text == text &&
      other.thumbCorners == thumbCorners;

  @override
  int get hashCode => Object.hashAll([
    width,
    plain,
    thumbnail,
    groupedPlain,
    groupedThumbnail,
    controlExtent,
    nameMaxLines,
    nameMaxLinesWithThumbnail,
    pullUp,
    pullUpWithThumbnail,
    trimBelow,
    trimBelowWithThumbnail,
    timeGrowth,
    footerLineHeight,
    infoShowsExtension,
    tooltipWhenElided,
    mirrorsInRtl,
    text,
    thumbCorners,
  ]);
}
