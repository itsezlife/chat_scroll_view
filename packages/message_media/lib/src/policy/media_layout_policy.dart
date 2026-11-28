import 'dart:math' as math;
import 'dart:ui';

import 'package:content_model/content_model.dart';
import 'package:message_media/src/diagnostics/media_op.dart';
import 'package:message_media/src/layout/media_layout.dart';
import 'package:message_media/src/layout/media_layout_input.dart';
import 'package:message_media/src/policy/desktop_mosaic_algorithm.dart';
import 'package:message_media/src/policy/ios_mosaic_algorithm.dart';
import 'package:message_media/src/policy/link_preview_card_policy.dart';
import 'package:message_media/src/policy/media_box_sizing.dart';
import 'package:message_media/src/policy/media_caption_width_policy.dart';
import 'package:message_media/src/policy/media_file_stack_policy.dart';
import 'package:message_media/src/policy/mosaic_algorithm.dart';
import 'package:meta/meta.dart';

/// The layout step of a message media policy: items in, a [MediaLayout]
/// out. Pure: the same input gives an equal layout.
///
/// [MediaLayoutPolicy] is the default; a host that lays media out its own
/// way implements this and hands it to the policy whole. The file rows and
/// the link preview card are the message media policy's own parts, which
/// the cells draw by too, so every step is handed them: a step that lays
/// files or cards out lays them by [fileStack] and [linkPreview], and what
/// it lays out is what the cells draw.
abstract interface class MediaLayoutStep {
  /// Lays [input] out, its file stacks by [fileStack] and its card by
  /// [linkPreview].
  MediaLayout layout(
    MediaLayoutInput input, {
    required MediaFileStackPolicy fileStack,
    required LinkPreviewCardPolicy linkPreview,
  });
}

/// The fit mode of each box kind alone, and of every box in an album.
///
/// | | Android | iOS | Desktop |
/// | --- | --- | --- | --- |
/// | [photo] | crop | blurFit (4 cropped) | cropIfVisible(0.75) |
/// | [video] | crop | crop | cropIfVisible(0.5) |
/// | [animation] | crop | crop | cropIfVisible(0.5) |
/// | [album] | crop | crop | crop |
///
/// The per-kind fits are for a box laid out alone, whose size follows its
/// picture; an album box's size follows the mosaic, so every platform fills
/// it.
@immutable
final class MediaFitPolicy {
  /// A fit per box kind alone, and the [album] fit.
  const MediaFitPolicy({
    required this.photo,
    required this.video,
    required this.animation,
    this.album = const MediaFit.crop(),
  });

  /// The Android family: every box crops.
  const MediaFitPolicy.android()
    : this(
        photo: const MediaFit.crop(),
        video: const MediaFit.crop(),
        animation: const MediaFit.crop(),
      );

  /// The iOS family: a photo fits over a blur with up to 4 cropped; video
  /// and animation fill.
  const MediaFitPolicy.ios()
    : this(
        photo: const MediaFit.blurFit(overflowCrop: 4),
        video: const MediaFit.crop(),
        animation: const MediaFit.crop(),
      );

  /// The desktop family: crop while 3/4 of a photo or 1/2 of a video or
  /// animation stays visible, otherwise a blurred fit.
  const MediaFitPolicy.desktop()
    : this(
        photo: const MediaFit.cropIfVisible(0.75),
        video: const MediaFit.cropIfVisible(0.5),
        animation: const MediaFit.cropIfVisible(0.5),
      );

  /// A photo's fit.
  final MediaFit photo;

  /// A video's fit.
  final MediaFit video;

  /// An animation's fit.
  final MediaFit animation;

  /// The fit of every box in a mosaic of two or more, whatever its kind.
  final MediaFit album;

  /// The fit of a box of [kind] laid out alone; null for a file row.
  MediaFit? fitOf(MediaItemKind kind) => switch (kind) {
    MediaItemKind.photo => photo,
    MediaItemKind.video => video,
    MediaItemKind.animation => animation,
    _ => null,
  };

  /// A copy with the given fits replaced.
  MediaFitPolicy copyWith({
    MediaFit? photo,
    MediaFit? video,
    MediaFit? animation,
    MediaFit? album,
  }) => MediaFitPolicy(
    photo: photo ?? this.photo,
    video: video ?? this.video,
    animation: animation ?? this.animation,
    album: album ?? this.album,
  );

  @override
  bool operator ==(Object other) =>
      other is MediaFitPolicy &&
      other.photo == photo &&
      other.video == video &&
      other.animation == animation &&
      other.album == album;

  @override
  int get hashCode => Object.hash(photo, video, animation, album);
}

/// The default layout step: boxes into mosaic blocks, file and custom kinds
/// into file stacks, the link preview into a card block last; each part a
/// replaceable value.
///
/// | Part | Role |
/// | --- | --- |
/// | [box] | A single box's size and a block's width |
/// | [mosaicAlgorithm] | Two or more boxes into a mosaic |
/// | [fit] | Each box kind's fit mode alone, and the album boxes' fit |
/// | [captionWidth] | The caption's width metrics (`widenMedia` / `wrapAtMedia`) |
///
/// ## Blocks
///
/// Consecutive boxes (pictures: photo, video, animation) make one mosaic
/// block: one box laid out alone, two or more by [mosaicAlgorithm] at the
/// block width. Consecutive file and custom items make one file stack. A
/// list mixing them gives consecutive blocks in item order, so every item
/// has exactly one cell. The file stack policy [layout] is handed lays a
/// stack's rows out, its width by its own rule rather than the box budget.
/// The link preview's card comes last, laid out by the card policy it is
/// handed; a removed or empty page makes no block.
///
/// ## Neighbours
///
/// The first block's top side touches the text when it, or a header, sits
/// above, else the bubble joined above, else the bubble's edge; the last
/// block's bottom
/// side likewise with the text below and the bubble joined below. Sides
/// between blocks, and the inner sides of a mosaic, touch an item. Left and
/// right outer sides are the bubble's edge.
///
/// ## Diagnostics
///
/// A custom kind laid out as a file row reports `media` / `unknownKind`
/// once per kind for each diagnostics sink (not on every layout pass); a
/// box that takes a fallback rule reports `media` / `layoutFallback`, both
/// with the item's id.
@immutable
final class MediaLayoutPolicy implements MediaLayoutStep {
  /// A layout step of the given parts.
  const MediaLayoutPolicy({
    required this.box,
    required this.fit,
    this.mosaicAlgorithm = const GroupedMosaicAlgorithm(),
    this.captionWidth = const MediaCaptionWidthPolicy.android(),
  });

  /// The Android family's layout.
  const MediaLayoutPolicy.android()
    : this(
        box: const MediaBoxSizing.android(),
        fit: const MediaFitPolicy.android(),
      );

  /// The iOS family's layout, with its own mosaic ([IosMosaicAlgorithm]).
  const MediaLayoutPolicy.ios()
    : this(
        box: const MediaBoxSizing.ios(),
        fit: const MediaFitPolicy.ios(),
        mosaicAlgorithm: const IosMosaicAlgorithm(),
        captionWidth: const MediaCaptionWidthPolicy.ios(),
      );

  /// The desktop family's layout, albums by [DesktopMosaicAlgorithm].
  const MediaLayoutPolicy.desktop()
    : this(
        box: const MediaBoxSizing.desktop(),
        fit: const MediaFitPolicy.desktop(),
        mosaicAlgorithm: const DesktopMosaicAlgorithm(),
        captionWidth: const MediaCaptionWidthPolicy.desktop(),
      );

  /// Box sizing.
  final MediaBoxSizing box;

  /// The mosaic slot.
  final MosaicAlgorithm mosaicAlgorithm;

  /// Fit modes.
  final MediaFitPolicy fit;

  /// The caption's width metrics.
  final MediaCaptionWidthPolicy captionWidth;

  // The custom kinds already reported as unknown, per diagnostics sink: a
  // layout runs on every rebuild, and one warning per kind says it all.
  static final Expando<Set<String>> _$reportedKinds = Expando();

  @override
  MediaLayout layout(
    MediaLayoutInput input, {
    required MediaFileStackPolicy fileStack,
    required LinkPreviewCardPolicy linkPreview,
  }) {
    final card = linkPreview;
    final runs = _runsOf(input);
    final showsCard = switch (input.linkPreview) {
      MediaLinkPreviewInput(:final page, :final options) =>
        !(options?.removed ?? false) && !LinkPreviewCardPolicy.isEmpty(page),
      null => false,
    };
    final blockCount = runs.length + (showsCard ? 1 : 0);
    final blocks = <MediaBlock>[];
    var top = 0.0;
    for (final (index, run) in runs.indexed) {
      final sides = _BlockSides.of(input, index: index, count: blockCount);
      final block = run.boxes
          ? _mosaic(run.items, input, top, sides)
          : fileStack.layout(
              run.items,
              input,
              top: top,
              topSide: sides.top,
              bottomSide: sides.bottom,
              isLastBlock: index == blockCount - 1,
            );
      blocks.add(block);
      top = block.rect.bottom;
    }
    if (card.layout(input, top: top, box: box) case final cardBlock?) {
      blocks.add(cardBlock);
      top = cardBlock.rect.bottom;
    }
    final width = blocks.fold<double>(
      0,
      (w, block) => math.max(w, block.rect.right),
    );
    return MediaLayout(
      size: Size(width, top),
      blocks: blocks,
      widthMetrics: captionWidth.metricsOf(
        input,
        mediaWidth: width,
        blockWidth: box.blockWidth(input),
      ),
    );
  }

  /// Consecutive items of the same layout (box or row), in item order.
  List<({bool boxes, List<MediaItem> items})> _runsOf(MediaLayoutInput input) {
    final runs = <({bool boxes, List<MediaItem> items})>[];
    for (final item in input.items) {
      final boxes = item.kind.isPicture;
      if (item.kind.isCustom && _firstReportOf(item.kind)) {
        ChatDiagnostics.current.emit(
          ChatEventLevel.warning,
          ChatEventCategory.media,
          MediaOp.unknownKind,
          correlation: _itemCorrelation(input, item),
          fields: () => {
            'kind': ChatEvent.clip(item.kind.value),
            'drawnAs': 'fileRow',
          },
        );
      }
      if (runs.isNotEmpty && runs.last.boxes == boxes) {
        runs.last.items.add(item);
      } else {
        runs.add((boxes: boxes, items: [item]));
      }
    }
    return runs;
  }

  // Whether [kind] is not yet reported to the current diagnostics sink;
  // marks it reported.
  static bool _firstReportOf(MediaItemKind kind) {
    final sink = ChatDiagnostics.current;
    final reported = _$reportedKinds[sink] ??= <String>{};
    return reported.add(kind.value);
  }

  MediaBlock _mosaic(
    List<MediaItem> items,
    MediaLayoutInput input,
    double top,
    _BlockSides sides,
  ) {
    if (items case [final item]) {
      final result = box.single(item, input);
      _reportFallbacks(input, item, result.fallbacks, result.size);
      final rect = Offset(0, top) & result.size;
      return MediaBlock.mosaic(
        rect: rect,
        cells: [
          MediaCell(
            itemId: item.id,
            kind: item.kind,
            rect: rect,
            fit: fit.fitOf(item.kind),
            neighbours: MediaNeighbours(
              top: sides.top,
              bottom: sides.bottom,
              left: MediaNeighbour.bubbleEdge,
              right: MediaNeighbour.bubbleEdge,
            ),
          ),
        ],
      );
    }
    final arrangement = mosaicAlgorithm.arrange(
      items: items,
      width: box.blockWidth(input),
      input: input,
    );
    final byId = {for (final item in items) item.id: item};
    final cells = <MediaCell>[];
    for (final placement in arrangement.placements) {
      final item = byId[placement.itemId];
      assert(
        item != null,
        '${mosaicAlgorithm.name} placed ${placement.itemId}, an item it was '
        'not given: an algorithm places exactly its items.',
      );
      if (item == null) continue;
      final rect = placement.rect.shift(Offset(0, top));
      if (item.descriptor.size == null) {
        _reportFallbacks(input, item, const {
          MediaLayoutFallbackRule.noDimensions,
        }, rect.size);
      }
      final edges = placement.edges;
      cells.add(
        MediaCell(
          itemId: item.id,
          kind: item.kind,
          rect: rect,
          fit: fit.album,
          neighbours: MediaNeighbours(
            top: edges.hasTop ? sides.top : MediaNeighbour.item,
            bottom: edges.hasBottom ? sides.bottom : MediaNeighbour.item,
            left: edges.hasLeft
                ? MediaNeighbour.bubbleEdge
                : MediaNeighbour.item,
            right: edges.hasRight
                ? MediaNeighbour.bubbleEdge
                : MediaNeighbour.item,
          ),
        ),
      );
    }
    return MediaBlock.mosaic(
      rect: Offset(0, top) & arrangement.size,
      cells: cells,
    );
  }

  static ChatCorrelation _itemCorrelation(
    MediaLayoutInput input,
    MediaItem item,
  ) => ChatCorrelation(
    chatId: input.correlation.chatId,
    scrollId: input.correlation.scrollId,
    clientMessageId: input.correlation.clientMessageId,
    mediaItemId: item.id.toString(),
  );

  static void _reportFallbacks(
    MediaLayoutInput input,
    MediaItem item,
    Set<MediaLayoutFallbackRule> rules,
    Size size,
  ) {
    for (final rule in rules) {
      ChatDiagnostics.current.emit(
        ChatEventLevel.debug,
        ChatEventCategory.media,
        MediaOp.layoutFallback,
        correlation: _itemCorrelation(input, item),
        fields: () => {
          'rule': rule,
          'width': size.width,
          'height': size.height,
        },
      );
    }
  }

  /// A copy with the given parts replaced.
  MediaLayoutPolicy copyWith({
    MediaBoxSizing? box,
    MosaicAlgorithm? mosaicAlgorithm,
    MediaFitPolicy? fit,
    MediaCaptionWidthPolicy? captionWidth,
  }) => MediaLayoutPolicy(
    box: box ?? this.box,
    mosaicAlgorithm: mosaicAlgorithm ?? this.mosaicAlgorithm,
    fit: fit ?? this.fit,
    captionWidth: captionWidth ?? this.captionWidth,
  );
}

/// What the outer top and bottom sides of one block touch.
final class _BlockSides {
  const _BlockSides(this.top, this.bottom);

  factory _BlockSides.of(
    MediaLayoutInput input, {
    required int index,
    required int count,
  }) => _BlockSides(
    switch ((index, input.captionPosition, input.joinedAbove)) {
      (> 0, _, _) => MediaNeighbour.item,
      (_, MediaCaptionPosition.above, _) => MediaNeighbour.text,
      _ when input.headerAbove => MediaNeighbour.text,
      (_, _, true) => MediaNeighbour.adjacentBubble,
      _ => MediaNeighbour.bubbleEdge,
    },
    switch ((count - 1 - index, input.captionPosition, input.joinedBelow)) {
      (> 0, _, _) => MediaNeighbour.item,
      (_, MediaCaptionPosition.below, _) => MediaNeighbour.text,
      (_, _, true) => MediaNeighbour.adjacentBubble,
      _ => MediaNeighbour.bubbleEdge,
    },
  );

  final MediaNeighbour top;
  final MediaNeighbour bottom;
}
