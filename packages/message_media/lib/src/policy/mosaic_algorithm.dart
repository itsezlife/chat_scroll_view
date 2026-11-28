import 'dart:math' as math;
import 'dart:ui';

import 'package:content_model/content_model.dart';
import 'package:message_media/src/grouped_message_position.dart';
import 'package:message_media/src/grouped_messages.dart';
import 'package:message_media/src/layout/media_layout_input.dart';
import 'package:message_media/src/media_layout_metrics.dart';
import 'package:message_media/src/mosaic_layout.dart';
import 'package:meta/meta.dart';

/// One box of a [MosaicArrangement]: its item, rect and the mosaic edges it
/// touches.
@immutable
final class MosaicPlacement {
  /// The box of [itemId] at [rect], on the mosaic's [edges].
  const MosaicPlacement({
    required this.itemId,
    required this.rect,
    required this.edges,
  });

  /// The item.
  final MediaItemId itemId;

  /// The box in mosaic-local coordinates.
  final Rect rect;

  /// The mosaic's outer edges the box lies on; a side without its flag
  /// touches another box.
  final GroupedPositionFlags edges;

  @override
  bool operator ==(Object other) =>
      other is MosaicPlacement &&
      other.itemId == itemId &&
      other.rect == rect &&
      other.edges == edges;

  @override
  int get hashCode => Object.hash(itemId, rect, edges);
}

/// Two or more boxes arranged by a [MosaicAlgorithm].
@immutable
final class MosaicArrangement {
  /// An arrangement of [placements] in a mosaic of [size].
  MosaicArrangement({
    required this.size,
    required List<MosaicPlacement> placements,
  }) : placements = List.unmodifiable(placements);

  /// The mosaic's outer size.
  final Size size;

  /// One placement per item, in item order.
  final List<MosaicPlacement> placements;
}

/// The slot that arranges two or more boxes into a mosaic.
///
/// Platforms arrange albums with different algorithms; each is one
/// implementation of this slot, and a host may plug its own.
abstract interface class MosaicAlgorithm {
  /// A stable name, logged by the layout's diagnostics.
  String get name;

  /// Arranges [items] (two or more boxes) in a mosaic [width] wide.
  MosaicArrangement arrange({
    required List<MediaItem> items,
    required double width,
    required MediaLayoutInput input,
  });
}

/// The default mosaic on every platform: [GroupedMessages.calculate]
/// projected by [MosaicLayout.project], with row heights bounded by the
/// screen.
///
/// | Field | Value | Role |
/// | --- | --- | --- |
/// | [maxHeightFactor] | 0.5 | Album max height = this × `max(listWidth, screenHeight)` |
/// | [cellGap] | 1 | Seam between boxes |
///
/// An item without dimensions is a square.
@immutable
final class GroupedMosaicAlgorithm implements MosaicAlgorithm {
  /// The default mosaic; either value can be replaced.
  const GroupedMosaicAlgorithm({
    this.maxHeightFactor = 0.5,
    this.cellGap = MediaLayoutMetrics.cellGap,
  });

  /// See the class table.
  final double maxHeightFactor;

  /// See the class table.
  final double cellGap;

  @override
  String get name => 'grouped';

  /// The album max height for [input]: a position's full height (`ph` of 1)
  /// in pixels.
  double maxHeightFor(MediaLayoutInput input) =>
      maxHeightFactor * math.max(input.availableWidth, input.displayHeight);

  @override
  MosaicArrangement arrange({
    required List<MediaItem> items,
    required double width,
    required MediaLayoutInput input,
  }) {
    final grouped = GroupedMessages.calculate(
      members: [
        for (final item in items)
          GroupedMediaMember(
            id: item.id,
            aspectRatio: switch (item.descriptor.size) {
              ContentSize(:final width, :final height) => width / height,
              null => 1,
            },
            kind: item.kind,
          ),
      ],
      isOut: input.isOutgoing,
      needShare: input.hasSideButton,
    );
    final mosaic = MosaicLayout.project(
      positions: grouped.positions,
      mosaicWidth: width,
      cellGap: cellGap,
      // A side button narrows the abstract width (750); the lines span that
      // width, so it maps to the mosaic's, which the box sizing has already
      // narrowed for the button.
      maxSizeWidth: grouped.maxSizeWidth.toDouble(),
      rowHeightUnit: maxHeightFor(input),
    );
    return MosaicArrangement(
      size: mosaic.size,
      placements: [
        for (final cell in mosaic.cells)
          MosaicPlacement(
            itemId: cell.itemId,
            rect: cell.rect,
            edges: cell.position.flags,
          ),
      ],
    );
  }

  /// A copy with the given values replaced.
  GroupedMosaicAlgorithm copyWith({double? maxHeightFactor, double? cellGap}) =>
      GroupedMosaicAlgorithm(
        maxHeightFactor: maxHeightFactor ?? this.maxHeightFactor,
        cellGap: cellGap ?? this.cellGap,
      );

  @override
  bool operator ==(Object other) =>
      other is GroupedMosaicAlgorithm &&
      other.maxHeightFactor == maxHeightFactor &&
      other.cellGap == cellGap;

  @override
  int get hashCode => Object.hash(maxHeightFactor, cellGap);
}
