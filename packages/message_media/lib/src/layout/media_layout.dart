import 'dart:ui';

import 'package:content_model/content_model.dart';
import 'package:flutter/foundation.dart';

// --- Neighbours ---

/// What a cell's side touches, which the paint step reads to pick the
/// corner radius on that side.
enum MediaNeighbour {
  /// The bubble's own outer edge.
  bubbleEdge,

  /// Text in the same bubble: the caption, or a link preview message's body.
  text,

  /// Another media cell or another block of the same media layout.
  item,

  /// The edge of a bubble the message is grouped with (the next or previous
  /// message from the same sender, drawn joined to this one).
  adjacentBubble,
}

/// A cell's [MediaNeighbour] on each of its four sides.
///
/// Sides are physical (left / right), as the rects are; the paint step maps
/// them for right-to-left lists.
@immutable
final class MediaNeighbours {
  /// The neighbours of each side.
  const MediaNeighbours({
    required this.top,
    required this.bottom,
    required this.left,
    required this.right,
  });

  /// Every side on the bubble's edge: a lone box in a media-only bubble.
  static const bubble = MediaNeighbours(
    top: MediaNeighbour.bubbleEdge,
    bottom: MediaNeighbour.bubbleEdge,
    left: MediaNeighbour.bubbleEdge,
    right: MediaNeighbour.bubbleEdge,
  );

  /// The top side.
  final MediaNeighbour top;

  /// The bottom side.
  final MediaNeighbour bottom;

  /// The left side.
  final MediaNeighbour left;

  /// The right side.
  final MediaNeighbour right;

  @override
  bool operator ==(Object other) =>
      other is MediaNeighbours &&
      other.top == top &&
      other.bottom == bottom &&
      other.left == left &&
      other.right == right;

  @override
  int get hashCode => Object.hash(top, bottom, left, right);

  @override
  String toString() =>
      'MediaNeighbours(top: ${top.name}, bottom: ${bottom.name}, '
      'left: ${left.name}, right: ${right.name})';
}

// --- Fit ---

/// How a box draws a picture whose aspect differs from the box's (a caption,
/// reactions or a minimum width widened the box).
@immutable
sealed class MediaFit {
  const MediaFit._();

  /// Centre crop to the box.
  const factory MediaFit.crop() = MediaFit$Crop;

  /// Fit the whole picture and fill the bars with a blur of it; a mismatch
  /// of up to [overflowCrop] logical pixels is cropped instead of barred.
  const factory MediaFit.blurFit({double overflowCrop}) = MediaFit$BlurFit;

  /// Crop when at least [fraction] of the picture stays visible, otherwise
  /// fit over a blurred copy.
  const factory MediaFit.cropIfVisible(double fraction) =
      MediaFit$CropIfVisible;
}

/// [MediaFit.crop].
final class MediaFit$Crop extends MediaFit {
  /// The crop fit.
  const MediaFit$Crop() : super._();

  @override
  bool operator ==(Object other) => other is MediaFit$Crop;

  @override
  int get hashCode => (MediaFit$Crop).hashCode;

  @override
  String toString() => 'MediaFit.crop';
}

/// [MediaFit.blurFit].
final class MediaFit$BlurFit extends MediaFit {
  /// A blurred fit cropping up to [overflowCrop].
  const MediaFit$BlurFit({this.overflowCrop = 0})
    : assert(overflowCrop >= 0, 'overflowCrop is not negative.'),
      super._();

  /// The largest mismatch, in logical pixels, cropped rather than barred.
  final double overflowCrop;

  @override
  bool operator ==(Object other) =>
      other is MediaFit$BlurFit && other.overflowCrop == overflowCrop;

  @override
  int get hashCode => Object.hash(MediaFit$BlurFit, overflowCrop);

  @override
  String toString() => 'MediaFit.blurFit(overflowCrop: $overflowCrop)';
}

/// [MediaFit.cropIfVisible].
final class MediaFit$CropIfVisible extends MediaFit {
  /// Crop while [fraction] of the picture stays visible.
  const MediaFit$CropIfVisible(this.fraction)
    : assert(fraction > 0 && fraction <= 1, 'fraction is in (0, 1].'),
      super._();

  /// The smallest visible share of the picture a crop may leave.
  final double fraction;

  @override
  bool operator ==(Object other) =>
      other is MediaFit$CropIfVisible && other.fraction == fraction;

  @override
  int get hashCode => Object.hash(MediaFit$CropIfVisible, fraction);

  @override
  String toString() => 'MediaFit.cropIfVisible($fraction)';
}

// --- Cells and blocks ---

/// One media item's place in a [MediaLayout].
@immutable
final class MediaCell {
  /// A cell of the item [itemId].
  const MediaCell({
    required this.itemId,
    required this.kind,
    required this.rect,
    required this.neighbours,
    this.fit,
  });

  /// The item this cell draws; it keys the cell across layouts.
  final MediaItemId itemId;

  /// The item's kind as laid out. A custom kind is a file row.
  final MediaItemKind kind;

  /// The cell's bounds in layout coordinates (origin at the layout's top
  /// left).
  final Rect rect;

  /// How the box draws a picture of another aspect; null for a file row,
  /// which has no box.
  final MediaFit? fit;

  /// What each side touches.
  final MediaNeighbours neighbours;

  @override
  bool operator ==(Object other) =>
      other is MediaCell &&
      other.itemId == itemId &&
      other.kind == kind &&
      other.rect == rect &&
      other.fit == fit &&
      other.neighbours == neighbours;

  @override
  int get hashCode => Object.hash(itemId, kind, rect, fit, neighbours);

  @override
  String toString() => 'MediaCell($itemId, ${kind.value}, $rect, $fit)';
}

/// One vertical run of a [MediaLayout]: boxes, file rows or a link preview
/// card.
@immutable
sealed class MediaBlock {
  const MediaBlock._({required this.rect});

  /// Boxes: one, or a mosaic of two or more.
  factory MediaBlock.mosaic({
    required Rect rect,
    required List<MediaCell> cells,
  }) = MediaBlock$Mosaic;

  /// File rows, one per item.
  factory MediaBlock.fileStack({
    required Rect rect,
    required List<MediaCell> cells,
  }) = MediaBlock$FileStack;

  /// The link preview card of [page].
  const factory MediaBlock.linkPreview({
    required Rect rect,
    required LinkPreview page,
    LinkPreviewOptions? options,
  }) = MediaBlock$LinkPreview;

  /// The block's bounds in layout coordinates.
  final Rect rect;

  /// The cells of the block, in item order.
  List<MediaCell> get cells;

  /// The block's kind, as a diagnostics event names it.
  String get kindName;
}

/// Photo, video and animation boxes: one box, or a mosaic of two or more.
final class MediaBlock$Mosaic extends MediaBlock {
  /// A mosaic block of [cells].
  MediaBlock$Mosaic({required super.rect, required List<MediaCell> cells})
    : cells = List.unmodifiable(cells),
      super._();

  @override
  final List<MediaCell> cells;

  @override
  String get kindName => 'mosaic';

  @override
  bool operator ==(Object other) =>
      other is MediaBlock$Mosaic &&
      other.rect == rect &&
      listEquals(other.cells, cells);

  @override
  int get hashCode =>
      Object.hash(MediaBlock$Mosaic, rect, Object.hashAll(cells));

  @override
  String toString() => 'MediaBlock.mosaic($rect, ${cells.length} cells)';
}

/// File and custom-kind rows stacked vertically, one row per item.
final class MediaBlock$FileStack extends MediaBlock {
  /// A file stack block of [cells].
  MediaBlock$FileStack({required super.rect, required List<MediaCell> cells})
    : cells = List.unmodifiable(cells),
      super._();

  @override
  final List<MediaCell> cells;

  @override
  String get kindName => 'fileStack';

  @override
  bool operator ==(Object other) =>
      other is MediaBlock$FileStack &&
      other.rect == rect &&
      listEquals(other.cells, cells);

  @override
  int get hashCode =>
      Object.hash(MediaBlock$FileStack, rect, Object.hashAll(cells));

  @override
  String toString() => 'MediaBlock.fileStack($rect, ${cells.length} rows)';
}

/// The link preview card: page data and the message's preview options.
///
/// Its [rect] is a placeholder (the card's own metrics are not laid out
/// yet): the width of the layout's box budget and no height.
final class MediaBlock$LinkPreview extends MediaBlock {
  /// The card of [page] with [options].
  const MediaBlock$LinkPreview({
    required super.rect,
    required this.page,
    this.options,
  }) : super._();

  /// The page the card shows.
  final LinkPreview page;

  /// The message's options for the preview, when it carries any.
  final LinkPreviewOptions? options;

  @override
  List<MediaCell> get cells => const [];

  @override
  String get kindName => 'linkPreview';

  @override
  bool operator ==(Object other) =>
      other is MediaBlock$LinkPreview &&
      other.rect == rect &&
      other.page == page &&
      other.options == options;

  @override
  int get hashCode => Object.hash(MediaBlock$LinkPreview, rect, page, options);

  @override
  String toString() => 'MediaBlock.linkPreview($rect)';
}

// --- Width metrics ---

/// How the caption's width and the media's width relate.
enum MediaCaptionWidthRule {
  /// The caption may be wider than the media; the media widens to match.
  widenMedia,

  /// The media's max width caps the bubble; the caption wraps there.
  wrapAtMedia,
}

/// The widths the bubble composes the caption with.
@immutable
final class MediaWidthMetrics {
  /// Metrics under [rule], wrapping the caption at [captionMaxWidth].
  const MediaWidthMetrics({required this.rule, required this.captionMaxWidth});

  /// How the caption and the media widths relate.
  final MediaCaptionWidthRule rule;

  /// The width the caption wraps at.
  final double captionMaxWidth;

  @override
  bool operator ==(Object other) =>
      other is MediaWidthMetrics &&
      other.rule == rule &&
      other.captionMaxWidth == captionMaxWidth;

  @override
  int get hashCode => Object.hash(rule, captionMaxWidth);
}

// --- Layout ---

/// A message's media laid out: ordered [blocks] of cells keyed by
/// [MediaItemId].
///
/// A value: two layouts of the same items compare equal when every block,
/// cell, rect, fit and neighbour does, and a cell is found by its item in
/// either ([cellOf]), so two layouts can be matched item by item.
@immutable
final class MediaLayout {
  /// A layout of [blocks] in a box of [size].
  MediaLayout({
    required this.size,
    required List<MediaBlock> blocks,
    this.widthMetrics,
    this.timePill,
  }) : blocks = List.unmodifiable(blocks),
       _cellsById = {
         for (final block in blocks)
           for (final cell in block.cells) cell.itemId: cell,
       };

  /// The empty layout: no items, no preview.
  static final empty = MediaLayout(size: Size.zero, blocks: const []);

  /// The bounds of every block together.
  final Size size;

  /// The blocks, top to bottom.
  final List<MediaBlock> blocks;

  /// The caption's widths; null until the bubble composition fills it.
  final MediaWidthMetrics? widthMetrics;

  /// The time pill's rect when the time sits on the media; null when it does
  /// not, or until the chrome slots fill it.
  final Rect? timePill;

  final Map<MediaItemId, MediaCell> _cellsById;

  /// Every cell, block by block, in item order.
  Iterable<MediaCell> get cells => blocks.expand((block) => block.cells);

  /// The cell of the item [id], or null when it is not laid out.
  MediaCell? cellOf(MediaItemId id) => _cellsById[id];

  @override
  bool operator ==(Object other) =>
      other is MediaLayout &&
      other.size == size &&
      other.widthMetrics == widthMetrics &&
      other.timePill == timePill &&
      listEquals(other.blocks, blocks);

  @override
  int get hashCode =>
      Object.hash(size, Object.hashAll(blocks), widthMetrics, timePill);

  @override
  String toString() => 'MediaLayout($size, $blocks)';
}
