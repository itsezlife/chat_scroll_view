import 'dart:math' as math;
import 'dart:ui';

import 'package:content_model/content_model.dart';
import 'package:flutter/foundation.dart';
import 'package:message_media/src/diagnostics/media_trace.dart';
import 'package:message_media/src/layout/media_corner_radii.dart';
import 'package:message_media/src/layout/media_file_row.dart';

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

  /// How a picture of [picture] size is drawn in a box of [box] size under
  /// this fit: cropped, or whole over blurred bars.
  ///
  /// A picture of unknown or empty size, or of the box's aspect, is cropped
  /// (there is nothing to bar).
  MediaFitDraw drawIn(Size box, Size? picture) {
    if (picture == null || picture.isEmpty || box.isEmpty) {
      return MediaFitDraw.crop;
    }
    final boxAspect = box.width / box.height;
    final pictureAspect = picture.width / picture.height;
    if (boxAspect == pictureAspect) return MediaFitDraw.crop;
    return switch (this) {
      MediaFit$Crop() => MediaFitDraw.crop,
      MediaFit$BlurFit(:final overflowCrop) =>
        // The bars a whole fit leaves, summed across the barred axis.
        (boxAspect > pictureAspect
                    ? box.width - box.height * pictureAspect
                    : box.height - box.width / pictureAspect) <=
                overflowCrop
            ? MediaFitDraw.crop
            : MediaFitDraw.blurredBars,
      MediaFit$CropIfVisible(:final fraction) =>
        // The share of the picture a crop keeps.
        math.min(boxAspect / pictureAspect, pictureAspect / boxAspect) >=
                fraction
            ? MediaFitDraw.crop
            : MediaFitDraw.blurredBars,
    };
  }
}

/// How a box draws its picture once its fit is decided for the picture's
/// size ([MediaFit.drawIn]).
enum MediaFitDraw {
  /// Centre crop to the box.
  crop,

  /// The whole picture, the bars filled with a blur of it (the blurred
  /// preview or thumbnail stage until the picture itself shows).
  blurredBars,
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
    this.radii = MediaCornerRadii.zero,
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

  /// The corner radii the paint step resolved from [neighbours]
  /// (`MediaCornerPolicy`); square until then.
  final MediaCornerRadii radii;

  /// A copy with the given fields replaced.
  MediaCell copyWith({
    Rect? rect,
    MediaFit? fit,
    MediaNeighbours? neighbours,
    MediaCornerRadii? radii,
  }) => MediaCell(
    itemId: itemId,
    kind: kind,
    rect: rect ?? this.rect,
    fit: fit ?? this.fit,
    neighbours: neighbours ?? this.neighbours,
    radii: radii ?? this.radii,
  );

  @override
  bool operator ==(Object other) =>
      other is MediaCell &&
      other.itemId == itemId &&
      other.kind == kind &&
      other.rect == rect &&
      other.fit == fit &&
      other.neighbours == neighbours &&
      other.radii == radii;

  @override
  int get hashCode => Object.hash(itemId, kind, rect, fit, neighbours, radii);

  @override
  String toString() => 'MediaCell($itemId, ${kind.value}, $rect, $fit, $radii)';
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

  /// File rows, one per item, each with its laid-out [rows] entry, and the
  /// [footer] line under the stack where the platform draws one.
  factory MediaBlock.fileStack({
    required Rect rect,
    required List<MediaCell> cells,
    List<MediaFileRow> rows,
    Rect? footer,
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

  /// This block with [cells] in place of its own (same count and order);
  /// a block without cells is returned as it is.
  MediaBlock withCells(List<MediaCell> cells);
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
  MediaBlock withCells(List<MediaCell> cells) =>
      MediaBlock$Mosaic(rect: rect, cells: cells);

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
///
/// [rows] holds each row's inner geometry (control or thumbnail, name, info
/// and link lines, caption slot), in the order of [cells]; a host's own
/// layout step may leave it empty. [footer] is the extra line some
/// platforms draw under a stack for views, signature or the edited mark.
final class MediaBlock$FileStack extends MediaBlock {
  /// A file stack block of [cells].
  MediaBlock$FileStack({
    required super.rect,
    required List<MediaCell> cells,
    List<MediaFileRow> rows = const [],
    this.footer,
  }) : cells = List.unmodifiable(cells),
       rows = List.unmodifiable(rows),
       super._();

  @override
  final List<MediaCell> cells;

  /// Each row's inner geometry, in item order.
  final List<MediaFileRow> rows;

  /// The extra line under the stack, in layout coordinates; null when none.
  final Rect? footer;

  /// The row of the item [id], or null when the block has none for it.
  MediaFileRow? rowOf(MediaItemId id) {
    for (final row in rows) {
      if (row.itemId == id) return row;
    }
    return null;
  }

  @override
  String get kindName => 'fileStack';

  @override
  MediaBlock withCells(List<MediaCell> cells) => MediaBlock$FileStack(
    rect: rect,
    cells: cells,
    rows: rows,
    footer: footer,
  );

  @override
  bool operator ==(Object other) =>
      other is MediaBlock$FileStack &&
      other.rect == rect &&
      other.footer == footer &&
      listEquals(other.cells, cells) &&
      listEquals(other.rows, rows);

  @override
  int get hashCode => Object.hash(
    MediaBlock$FileStack,
    rect,
    footer,
    Object.hashAll(cells),
    Object.hashAll(rows),
  );

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
  MediaBlock withCells(List<MediaCell> cells) => this;

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
/// either ([cellOf]), so two layouts can be matched item by item, which is
/// what [lerp] does.
@immutable
final class MediaLayout {
  /// A layout of [blocks] in a box of [size].
  MediaLayout({
    required this.size,
    required List<MediaBlock> blocks,
    this.widthMetrics,
    this.timePill,
    List<MediaCell> exiting = const [],
  }) : blocks = List.unmodifiable(blocks),
       exiting = List.unmodifiable(exiting),
       _cellsById = {
         for (final block in blocks)
           for (final cell in block.cells) cell.itemId: cell,
       };

  /// The layout [t] of the way from [a] to [b], matching cells by item.
  ///
  /// - A cell in both interpolates its rect and, when [radii] is set, each
  ///   corner's radius; without [radii] the corners snap to [b]'s. Its fit,
  ///   kind and neighbours are [b]'s: they snap.
  /// - A cell only in [b] sits at its [b] rect (it enters; the transition
  ///   fades it in).
  /// - A cell only in [a], or among [a]'s [exiting], is in the result's
  ///   [exiting] at its [a] rect (it leaves; the transition fades it out).
  ///   A cell of [a]'s [exiting] that is back in [b] moves from its exit
  ///   rect.
  /// - A block of [b] interpolates its rect from the block of [a] of the
  ///   same kind that shares a cell with it, else from the block of that
  ///   kind at the same index (a link preview card from [a]'s card); a
  ///   block with no match takes its [b] rect.
  /// - The size, the time pill and the caption's wrap width interpolate;
  ///   a time pill or metrics present on one side only take [b]'s, and the
  ///   caption width rule snaps.
  ///
  /// So `lerp(a, b, 1)` is [b] plus the cells that left, and a transition
  /// interrupted mid-flight starts its next leg from the frame it reached.
  factory MediaLayout.lerp(
    MediaLayout a,
    MediaLayout b,
    double t, {
    bool radii = true,
  }) {
    MediaTrace.begin(MediaTrace.lerp);
    final from = <MediaItemId, MediaCell>{
      for (final cell in a.exiting) cell.itemId: cell,
      for (final cell in a.cells) cell.itemId: cell,
    };
    final blocks = [
      for (final (index, block) in b.blocks.indexed)
        _lerpBlock(_matchOf(a, block, index), block, from, t, radii: radii),
    ];
    final exiting = [
      for (final cell in from.values)
        if (b.cellOf(cell.itemId) == null) cell,
    ];
    final result = MediaLayout(
      size: Size.lerp(a.size, b.size, t)!,
      blocks: blocks,
      widthMetrics: switch ((a.widthMetrics, b.widthMetrics)) {
        (final from?, final to?) => MediaWidthMetrics(
          rule: to.rule,
          captionMaxWidth: lerpDouble(
            from.captionMaxWidth,
            to.captionMaxWidth,
            t,
          )!,
        ),
        (_, final to) => to,
      },
      timePill: switch ((a.timePill, b.timePill)) {
        (final from?, final to?) => Rect.lerp(from, to, t),
        (_, final to) => to,
      },
      exiting: exiting,
    );
    MediaTrace.end(MediaTrace.lerp);
    return result;
  }

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

  /// Cells of items that left the layout and are still painted at their
  /// last rect while a transition fades them out; empty outside one.
  ///
  /// They are not among [cells] and [cellOf] does not find them: they are
  /// on their way out, not laid out.
  final List<MediaCell> exiting;

  final Map<MediaItemId, MediaCell> _cellsById;

  /// Every cell, block by block, in item order.
  Iterable<MediaCell> get cells => blocks.expand((block) => block.cells);

  /// The cell of the item [id], or null when it is not laid out.
  MediaCell? cellOf(MediaItemId id) => _cellsById[id];

  /// This layout with every cell passed through [map] (which keeps its
  /// item); the same layout when [map] changes no cell.
  MediaLayout mapCells(MediaCell Function(MediaCell cell) map) {
    var changed = false;
    final mapped = <MediaBlock>[];
    for (final block in blocks) {
      if (block.cells.isEmpty) {
        mapped.add(block);
        continue;
      }
      final cells = [for (final cell in block.cells) map(cell)];
      assert(
        cells.indexed.every(
          (entry) => entry.$2.itemId == block.cells[entry.$1].itemId,
        ),
        'mapCells keeps each cell on its item.',
      );
      if (listEquals(cells, block.cells)) {
        mapped.add(block);
      } else {
        changed = true;
        mapped.add(block.withCells(cells));
      }
    }
    if (!changed) return this;
    return MediaLayout(
      size: size,
      blocks: mapped,
      widthMetrics: widthMetrics,
      timePill: timePill,
      exiting: exiting,
    );
  }

  /// This layout with [exiting] in place of its own exiting cells.
  MediaLayout withExiting(List<MediaCell> exiting) => MediaLayout(
    size: size,
    blocks: blocks,
    widthMetrics: widthMetrics,
    timePill: timePill,
    exiting: exiting,
  );

  /// The block of [a] that [block] (at [index] in its layout) moves from.
  static MediaBlock? _matchOf(MediaLayout a, MediaBlock block, int index) {
    bool sameKind(MediaBlock other) => other.kindName == block.kindName;
    final ids = {for (final cell in block.cells) cell.itemId};
    for (final other in a.blocks) {
      if (!sameKind(other)) continue;
      final shares = switch (other) {
        // A message has one card: it is the same card in both.
        MediaBlock$LinkPreview() => true,
        _ => other.cells.any((cell) => ids.contains(cell.itemId)),
      };
      if (shares) return other;
    }
    if (index < a.blocks.length && sameKind(a.blocks[index])) {
      return a.blocks[index];
    }
    return null;
  }

  static MediaBlock _lerpBlock(
    MediaBlock? match,
    MediaBlock block,
    Map<MediaItemId, MediaCell> from,
    double t, {
    required bool radii,
  }) {
    final rect = switch (match) {
      final match? => Rect.lerp(match.rect, block.rect, t)!,
      null => block.rect,
    };
    final cells = [
      for (final cell in block.cells)
        switch (from[cell.itemId]) {
          final old? => cell.copyWith(
            rect: Rect.lerp(old.rect, cell.rect, t),
            radii: radii
                ? MediaCornerRadii.lerp(old.radii, cell.radii, t)
                : cell.radii,
          ),
          null => cell,
        },
    ];
    return switch (block) {
      MediaBlock$Mosaic() => MediaBlock$Mosaic(rect: rect, cells: cells),
      // A row's inner geometry snaps to the new layout's; the footer line
      // moves with the block.
      MediaBlock$FileStack(:final rows, :final footer) => MediaBlock$FileStack(
        rect: rect,
        cells: cells,
        rows: rows,
        footer: switch ((match, footer)) {
          (MediaBlock$FileStack(footer: final old?), final now?) => Rect.lerp(
            old,
            now,
            t,
          ),
          _ => footer,
        },
      ),
      MediaBlock$LinkPreview(:final page, :final options) =>
        MediaBlock$LinkPreview(rect: rect, page: page, options: options),
    };
  }

  @override
  bool operator ==(Object other) =>
      other is MediaLayout &&
      other.size == size &&
      other.widthMetrics == widthMetrics &&
      other.timePill == timePill &&
      listEquals(other.blocks, blocks) &&
      listEquals(other.exiting, exiting);

  @override
  int get hashCode => Object.hash(
    size,
    Object.hashAll(blocks),
    widthMetrics,
    timePill,
    Object.hashAll(exiting),
  );

  @override
  String toString() => 'MediaLayout($size, $blocks)';
}
