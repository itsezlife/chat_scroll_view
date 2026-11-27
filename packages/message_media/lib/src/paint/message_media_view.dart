import 'package:chat_scroll_view/chat_scroll_view.dart'
    show ChatSelectionController;
import 'package:content_assets/content_assets.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/widgets.dart';
import 'package:message_media/src/chrome/media_cell_chrome.dart';
import 'package:message_media/src/chrome/media_options_affordance.dart';
import 'package:message_media/src/diagnostics/media_op.dart';
import 'package:message_media/src/diagnostics/media_trace.dart';
import 'package:message_media/src/gesture/media_viewer_request.dart';
import 'package:message_media/src/layout/media_layout.dart';
import 'package:message_media/src/message_media_hit_part.dart';
import 'package:message_media/src/outgoing/media_send_flight.dart';
import 'package:message_media/src/outgoing/media_send_state.dart';
import 'package:message_media/src/paint/link_preview_card_view.dart';
import 'package:message_media/src/paint/media_cell_builders.dart';
import 'package:message_media/src/paint/message_media_body.dart';
import 'package:message_media/src/policy/media_layout_policy.dart';
import 'package:message_media/src/policy/message_media_policy.dart';
import 'package:message_media/src/state/message_media_state.dart';
import 'package:message_media/src/state/message_media_state_scope.dart';
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
/// sits above the view.
///
/// ## Gestures
///
/// With a [selection] facade and the [messageId], the view registers as the
/// message's non-text body and the viewport arbitrates every tap on it as a
/// body part hit (`ChatInlineHit.bodyPart` with a [MediaHitPart]): the
/// content, the status control, a hidden spoiler, the options affordance.
/// In message selection each toggles the message; a long press is always
/// the message's. In normal mode the view performs the part's action as the
/// policy's [MessageMediaPolicy.gestures] say: the content opens the host's
/// viewer through [onOpenViewer] (or cancels a load where the policy says),
/// the status control downloads or cancels, a hidden spoiler is revealed.
/// The options affordance opens the message menu, the request carrying the
/// part. A burst of activations acts once. On desktop the cursor is the
/// click cursor over a part and the item under the mouse is highlighted.
/// Without a facade the view takes no gesture.
///
/// ## Semantics
///
/// One node per item: its kind, then its duration or size, then its
/// progress while it loads, worded by [MessageMediaPolicy.semantics]. The
/// node's tap opens the item (reveals its spoiler); the status control and
/// the options affordance are separate actions ([onItemMenu]). In message
/// selection the node's only action is the toggle.
///
/// ## Viewer origin
///
/// A [MediaViewerRequest] carries the item's rectangle when it was tapped
/// and a lookup of any item's rectangle by id (`MessageMediaState.rectOf`),
/// which answers for every mounted view of the chat.
///
/// ## Chrome
///
/// Over each cell lie the policy's chrome slots (`MessageMediaPolicy.chrome`):
/// a spoiler's cover until the item is revealed, revealed per item in the
/// chat's `MessageMediaState` (the scope's, else the view's own), and the
/// options affordance where the placement puts one, fading out as
/// [selectionProgress] rises. The time pill is the host's, at
/// `MediaLayout.timePill`.
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
/// ## Outgoing
///
/// For a message being sent the host passes its [sendState]. In a scope
/// with tracked transfers each item's status control shows its upload by
/// the item's media key: the ring with the bytes sent and an upload's
/// cancel, then the sent check until the content is published. The cancel
/// is the item's cross: it reaches the upload's owner through the scope's
/// `TrackedTransfers.cancel`, which drops the item from its job, and
/// [onItemCancelled] tells the host the item's id, so the item leaves the
/// message's list and exits under the layout transition. A message whose
/// send failed shows no status control (the error badge and Retry / Delete
/// are the host's). Where the policy's [MessageMediaPolicy.sendFlight]
/// flies (iOS), a cell built for the first time asks the chat's
/// `MessageMediaState.takeSendOrigin` once and flies in from that rect.
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
    this.chromeContext = MediaChromeContext.none,
    this.selectionProgress,
    this.fades = const {},
    this.selection,
    this.messageId,
    this.onOpenViewer,
    this.onItemMenu,
    this.onLinkPreview,
    this.linkPreviewColors = LinkPreviewCardColors.fallback,
    this.cardOpacity = 1,
    this.leavingCard,
    this.leavingCardOpacity = 0,
    this.sendState = MediaSendState.none,
    this.onItemCancelled,
    super.key,
  }) : assert(
         selection == null || messageId != null,
         'A view that takes gestures names its message.',
       ),
       items = {
         for (final item in items) item.id: item,
         // A card's media item comes with its block.
         for (final block in layout.blocks)
           if (block case MediaBlock$LinkPreview(:final item?)) item.id: item,
       };

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

  /// What the message is drawn in (compact mode, a preview), which the
  /// chrome slots weigh.
  final MediaChromeContext chromeContext;

  /// The selection checkbox's appearance, 0 to 1, which fades the options
  /// affordance out; null is no checkbox.
  final Animation<double>? selectionProgress;

  /// The fades of the cells a transition fades in or out; a cell not here
  /// paints fully.
  final Map<MediaItemId, MediaCellFade> fades;

  /// The selection facade of the chat list the message is in; null for a
  /// view that takes no gestures.
  final ChatSelectionController? selection;

  /// The engine's id of the message, which the view registers under.
  final int? messageId;

  /// Opens the host's viewer on an activated item; null opens nothing (the
  /// host still hears the activation from the facade).
  final ValueChanged<MediaViewerRequest>? onOpenViewer;

  /// Opens the message menu for an item from the options affordance's
  /// semantics action, with the affordance's global rect; null drops that
  /// action. A pointer reaches the menu through the viewport.
  final void Function(MediaHitPart part, Rect rect)? onItemMenu;

  /// Called when the link preview card's body (open the page) or button
  /// (run its action) is activated; null does nothing (the host still hears
  /// the activation from the facade).
  final LinkPreviewActivated? onLinkPreview;

  /// The link preview card's colours: the sender's colour on an incoming
  /// message, the bubble's accent on an outgoing one.
  final LinkPreviewCardColors linkPreviewColors;

  /// The card's opacity while a transition fades it in.
  final double cardOpacity;

  /// A card a transition fades out (removed, or replaced by a new page).
  final MediaBlock$LinkPreview? leavingCard;

  /// The leaving card's opacity.
  final double leavingCardOpacity;

  /// Where the message stands if it is being sent.
  final MediaSendState sendState;

  /// Called with the item whose cross was tapped on a message being sent,
  /// after the cancel went to the upload's owner; the host takes the item
  /// out of the message (or tells an owner that names items by id). Null
  /// tells no one.
  final ValueChanged<MediaItemId>? onItemCancelled;

  @override
  Widget build(BuildContext context) => SizedBox.fromSize(
    size: layout.size,
    child: MessageMediaStateBuilder(
      scrollId: correlation.scrollId,
      builder: (context, state) => MessageMediaBody(
        layout: layout,
        items: items,
        policy: policy,
        state: state,
        dataOf: _dataOf,
        cellBuilder: (context, block, cell, decorate, {origin = Offset.zero}) =>
            _positioned(context, state, block, cell, decorate, origin),
        selection: selection,
        messageId: messageId,
        onOpenViewer: onOpenViewer,
        onItemMenu: onItemMenu,
        onLinkPreview: onLinkPreview,
        linkPreviewColors: linkPreviewColors,
        cardOpacity: cardOpacity,
        leavingCard: leavingCard,
        leavingCardOpacity: leavingCardOpacity,
        chromeContext: chromeContext,
        correlation: correlation,
        sendState: sendState,
        onItemCancelled: onItemCancelled,
      ),
    ),
  );

  Widget _positioned(
    BuildContext context,
    MessageMediaState state,
    MediaBlock block,
    MediaCell cell,
    MediaCellDecorator decorate,
    Offset origin,
  ) {
    final fade = fades[cell.itemId] ?? MediaCellFade.settled;
    return Positioned.fromRect(
      key: ValueKey(cell.itemId),
      rect: cell.rect.shift(-origin),
      child: Opacity(
        opacity: fade.opacity,
        child: Transform.scale(
          scale: fade.scale,
          child: _flown(
            state,
            block,
            cell,
            decorate(block, cell, _chromed(context, state, block, cell)),
          ),
        ),
      ),
    );
  }

  Widget _flown(
    MessageMediaState state,
    MediaBlock block,
    MediaCell cell,
    Widget child,
  ) => MediaSendFlight(
    itemId: cell.itemId,
    size: cell.rect.size,
    state: state,
    policy: policy.sendFlight,
    family: policy.family,
    correlation: correlation,
    flying: (context) => _cell(context, block, cell),
    child: child,
  );

  Widget _chromed(
    BuildContext context,
    MessageMediaState state,
    MediaBlock block,
    MediaCell cell,
  ) {
    final child = _traced(context, block, cell);
    final item = items[cell.itemId];
    if (item == null) return child;
    return MediaCellChrome(
      cell: cell,
      item: item,
      block: block,
      family: policy.family,
      slots: policy.chrome,
      state: state,
      context: chromeContext,
      selectionProgress: selectionProgress,
      downloadContext: downloadContext,
      correlation: correlation,
      child: child,
    );
  }

  Widget _traced(BuildContext context, MediaBlock block, MediaCell cell) {
    MediaTrace.begin(MediaTrace.cellBuild);
    final built = _cell(context, block, cell);
    MediaTrace.end(MediaTrace.cellBuild);
    return built;
  }

  Widget _cell(BuildContext context, MediaBlock block, MediaCell cell) {
    final builderName = MediaLayoutPolicy.isBox(cell.kind) ? 'box' : 'row';
    final data = _dataOf(block, cell);
    if (data == null) {
      _report(cell, null, builderName, 'missingItem');
      return const SizedBox.shrink();
    }
    final item = data.item;
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

  MediaCellData? _dataOf(MediaBlock block, MediaCell cell) {
    final item = items[cell.itemId];
    if (item == null) return null;
    final isRow = !MediaLayoutPolicy.isBox(cell.kind);
    return MediaCellData(
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
      chrome: policy.chrome,
      correlation: correlation,
      sendState: sendState,
    );
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
