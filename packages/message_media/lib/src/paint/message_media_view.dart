import 'package:content_assets/content_assets.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/widgets.dart';
import 'package:message_media/src/diagnostics/media_op.dart';
import 'package:message_media/src/diagnostics/media_trace.dart';
import 'package:message_media/src/layout/media_layout.dart';
import 'package:message_media/src/paint/media_cell_builders.dart';
import 'package:message_media/src/policy/media_layout_policy.dart';
import 'package:message_media/src/policy/message_media_policy.dart';
import 'package:message_media/src/transition/media_layout_transition.dart';
import 'package:mpx_core/mpx_core.dart';

/// Paints a [MediaLayout]: each cell at its rect, built by the [policy]'s
/// cell builder for its kind.
///
/// The view is the layout's size. Each cell is keyed by its
/// `MediaItemId`, so a cell keeps its element, and with it its binding,
/// decoder and spoiler state, across any re-layout that moves or resizes
/// it; only an item that leaves the layout loses its cell.
///
/// The cells draw through the asset pipeline, so a `ContentAssetProvider`
/// sits above the view. No gestures yet: taps and the long press reach the
/// message through the body part hit.
///
/// ## Transitions
///
/// A frame of a layout transition paints the same way: [layout] is the
/// interpolated layout, whose exiting cells paint after the others at their
/// last rect, and [fades] fades and scales the cells entering or leaving.
/// Every cell sits under the same fade wrapper whether it fades or not, so
/// a transition starting or ending never rebuilds a cell; and because each
/// cell is sized to its interpolated rect, its status control re-centres
/// on that rect every frame. `MessageMediaTransition` drives the frames.
///
/// ## Diagnostics
///
/// A builder that throws, or a cell whose item is not among [items],
/// reports `media` / `cellFailed` (error) with the builder and the error
/// type, and the cell draws nothing.
class MessageMediaView extends StatelessWidget {
  /// Paints [layout] of [items] as [policy] says.
  MessageMediaView({
    required this.layout,
    required List<MediaItem> items,
    required this.policy,
    this.downloadContext,
    this.correlation = ChatCorrelation.none,
    this.fades = const {},
    super.key,
  }) : items = {for (final item in items) item.id: item};

  /// The layout painted, with its corner radii resolved
  /// ([MessageMediaPolicy.layout] resolves them).
  final MediaLayout layout;

  /// The items laid out, by id.
  final Map<MediaItemId, MediaItem> items;

  /// The policy whose cell builders and autoplay the cells follow.
  final MessageMediaPolicy policy;

  /// The class of conversation the media is shown in, which the scope's
  /// auto-download rules weigh.
  final AutoDownloadContext? downloadContext;

  /// The chat and message the view's diagnostics events name.
  final ChatCorrelation correlation;

  /// The fades of the cells a transition fades in or out; a cell not here
  /// paints fully.
  final Map<MediaItemId, MediaCellFade> fades;

  @override
  Widget build(BuildContext context) => SizedBox.fromSize(
    size: layout.size,
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        for (final block in layout.blocks)
          for (final cell in block.cells) _positioned(context, block, cell),
        for (final cell in layout.exiting)
          _positioned(context, _blockOfExiting(cell), cell),
      ],
    ),
  );

  Widget _positioned(BuildContext context, MediaBlock block, MediaCell cell) {
    final fade = fades[cell.itemId] ?? MediaCellFade.settled;
    return Positioned.fromRect(
      key: ValueKey(cell.itemId),
      rect: cell.rect,
      child: Opacity(
        opacity: fade.opacity,
        child: Transform.scale(
          scale: fade.scale,
          child: _traced(context, block, cell),
        ),
      ),
    );
  }

  /// The one-cell block an exiting cell is drawn in: its own block is gone.
  static MediaBlock _blockOfExiting(MediaCell cell) =>
      MediaLayoutPolicy.isBox(cell.kind)
      ? MediaBlock.mosaic(rect: cell.rect, cells: [cell])
      : MediaBlock.fileStack(rect: cell.rect, cells: [cell]);

  Widget _traced(BuildContext context, MediaBlock block, MediaCell cell) {
    MediaTrace.begin(MediaTrace.cellBuild);
    final built = _cell(context, block, cell);
    MediaTrace.end(MediaTrace.cellBuild);
    return built;
  }

  Widget _cell(BuildContext context, MediaBlock block, MediaCell cell) {
    final builderName = MediaLayoutPolicy.isBox(cell.kind) ? 'box' : 'row';
    final item = items[cell.itemId];
    if (item == null) {
      _report(cell, null, builderName, 'missingItem');
      return const SizedBox.shrink();
    }
    final isRow = !MediaLayoutPolicy.isBox(cell.kind);
    final data = MediaCellData(
      cell: cell,
      item: item,
      block: block,
      family: policy.family,
      autoplay: policy.autoplay.plays(cell, block),
      downloadContext: downloadContext,
      fileRow: switch (block) {
        MediaBlock$FileStack() => block.rowOf(cell.itemId),
        _ => null,
      },
      fileStack: isRow ? policy.fileStack : null,
    );
    try {
      return policy.cells.of(cell.kind)(context, data);
    } on Object catch (error, stackTrace) {
      _report(cell, item, builderName, error.runtimeType.toString());
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'message_media',
          context: ErrorDescription('while building a media cell'),
        ),
      );
      return const SizedBox.shrink();
    }
  }

  void _report(
    MediaCell cell,
    MediaItem? item,
    String builder,
    String errorType,
  ) {
    ChatDiagnostics.current.emit(
      ChatEventLevel.error,
      ChatEventCategory.media,
      MediaOp.cellFailed,
      correlation: ChatCorrelation(
        chatId: correlation.chatId,
        scrollId: correlation.scrollId,
        clientMessageId: correlation.clientMessageId,
        mediaItemId: cell.itemId.toString(),
        mediaKey: item?.descriptor.key.mediaKey.encoded,
      ),
      fields: () => {
        'builder': builder,
        'errorType': ChatEvent.clip(errorType),
      },
    );
  }
}
