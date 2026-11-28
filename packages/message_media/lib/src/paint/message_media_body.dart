import 'package:chat_scroll_view/chat_scroll_view.dart'
    show
        ChatBodyPartActivated,
        ChatInlineHit,
        ChatNonTextBody,
        ChatSelectionController,
        ChatSelectionInteraction;
import 'package:chrome_foundation/chrome_foundation.dart'
    show ChromeStringsScope;
import 'package:content_assets/content_assets.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/gestures.dart' show PointerExitEvent, PointerHoverEvent;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:message_media/src/chrome/media_chrome_slots.dart';
import 'package:message_media/src/chrome/media_options_affordance.dart';
import 'package:message_media/src/diagnostics/media_op.dart';
import 'package:message_media/src/gesture/media_gesture_policy.dart';
import 'package:message_media/src/gesture/media_semantics_labels.dart';
import 'package:message_media/src/gesture/media_viewer_request.dart';
import 'package:message_media/src/layout/link_preview_card.dart';
import 'package:message_media/src/layout/media_layout.dart';
import 'package:message_media/src/message_media_hit_part.dart';
import 'package:message_media/src/outgoing/media_send_state.dart';
import 'package:message_media/src/paint/link_preview_card_view.dart';
import 'package:message_media/src/paint/media_box_cell.dart';
import 'package:message_media/src/paint/media_cell_builders.dart';
import 'package:message_media/src/paint/media_row_cell.dart';
import 'package:message_media/src/policy/message_media_policy.dart';
import 'package:message_media/src/state/message_media_state.dart';
import 'package:meta/meta.dart';
import 'package:mpx_core/mpx_core.dart';

/// Wraps a built cell in what the body adds over it (its semantics node,
/// its hover highlight).
@internal
typedef MediaCellDecorator =
    Widget Function(MediaBlock block, MediaCell cell, Widget built);

/// Builds one cell of the view at its place, chrome included, with
/// [decorate] around the cell inside its place; [origin] is the top-left of
/// the stack it is placed in, in layout coordinates (a card's, for the
/// card's media).
@internal
typedef MediaBodyCellBuilder =
    Widget Function(
      BuildContext context,
      MediaBlock block,
      MediaCell cell,
      MediaCellDecorator decorate, {
      Offset origin,
    });

/// Called with the zone of a link preview card the user activated and the
/// page: the host opens the page's URL ([LinkPreviewZone.body]) or runs the
/// button's action ([LinkPreviewZone.button]).
typedef LinkPreviewActivated =
    void Function(LinkPreviewHitPart part, LinkPreview page);

/// The media of one message as the viewport sees it: a non-text body whose
/// parts are body part hits, the actions those parts take in normal mode,
/// the mouse cursor and hover, one semantics node per item, and the items'
/// rectangles for the viewer.
///
/// ## Hits
///
/// Registered with the selection facade under [messageId]
/// (`ChatSelectionController.putNonTextBody`), it answers [inlineHitAt]
/// with `ChatInlineHit.bodyPart` carrying a [MediaHitPart], in this order:
/// an options affordance's hit area (which may reach past its cell), a
/// hidden spoiler (the whole cell), the status control while it offers a
/// download or a cancel, else the content. No detector of the media's own
/// takes a tap, so the viewport arbitrates every one: in message selection
/// each part toggles the message, and a long press is the message's.
///
/// ## Actions
///
/// A `ChatBodyPartActivated` naming one of the message's items is performed
/// here, as [MediaGesturePolicy.actionOf] says: the viewer opens through
/// [onOpenViewer], the item's binding downloads or cancels, the spoiler is
/// revealed from the touch point. An activation within the policy's
/// [MediaGesturePolicy.activationGuard] of the last accepted one is dropped
/// (`media` / `activationDropped`).
///
/// On a message being sent ([sendState]) a cancel on an item's status
/// control, or any upload's cancel, is the item's cross: the binding's
/// cancel reaches the upload's owner (`TrackedTransfers.cancel`), and
/// [onItemCancelled] hears the item (`media` / `itemCancelled`). A message
/// whose send failed has no status part.
///
/// ## Bindings
///
/// Each item has a binding of the view's own, attached with its cell's
/// preset so that it shares the cell's cache entry: what the status part,
/// the actions and the semantics read and command. Without a
/// `ContentAssetProvider` there are none, and the status part never shows.
/// Each binding's upload state is watched: a change between sending, sent
/// and none reports `media` / `uploadState`.
@internal
class MessageMediaBody extends StatefulWidget {
  /// The body of [layout] of [items].
  const MessageMediaBody({
    required this.layout,
    required this.items,
    required this.policy,
    required this.state,
    required this.dataOf,
    required this.cellBuilder,
    this.selection,
    this.messageId,
    this.onOpenViewer,
    this.onItemMenu,
    this.onLinkPreview,
    this.linkPreviewColors,
    this.cardOpacity = 1,
    this.leavingCard,
    this.leavingCardOpacity = 0,
    this.chromeContext = MediaChromeContext.none,
    this.correlation = ChatCorrelation.none,
    this.sendState = MediaSendState.none,
    this.onItemCancelled,
    super.key,
  });

  /// The layout painted.
  final MediaLayout layout;

  /// The items laid out, by id.
  final Map<MediaItemId, MediaItem> items;

  /// The policy whose gestures and strings the body follows.
  final MessageMediaPolicy policy;

  /// The chat's media state (spoilers, origins).
  final MessageMediaState state;

  /// The data the cell builder of a cell gets, or null for a cell whose
  /// item is missing.
  final MediaCellData? Function(MediaBlock block, MediaCell cell) dataOf;

  /// Builds a cell with its chrome.
  final MediaBodyCellBuilder cellBuilder;

  /// The selection facade the body registers with; null for a view outside
  /// a chat list, which takes no gestures.
  final ChatSelectionController? selection;

  /// The engine's id of the message.
  final int? messageId;

  /// Opens the host's viewer.
  final ValueChanged<MediaViewerRequest>? onOpenViewer;

  /// Opens the message menu for an item, from the options affordance's
  /// semantics action (a pointer reaches the menu through the viewport).
  final void Function(MediaHitPart part, Rect rect)? onItemMenu;

  /// What the message is drawn in.
  final MediaChromeContext chromeContext;

  /// Called when a link preview card's body or button is activated.
  final LinkPreviewActivated? onLinkPreview;

  /// The link preview card's colours.
  final LinkPreviewCardColors? linkPreviewColors;

  /// The card's opacity while it fades in.
  final double cardOpacity;

  /// A card on its way out, painted bare at [leavingCardOpacity].
  final MediaBlock$LinkPreview? leavingCard;

  /// The leaving card's opacity.
  final double leavingCardOpacity;

  /// The ids the body's events name.
  final ChatCorrelation correlation;

  /// Where the message stands if it is being sent.
  final MediaSendState sendState;

  /// Hears the item whose cross was tapped.
  final ValueChanged<MediaItemId>? onItemCancelled;

  @override
  State<MessageMediaBody> createState() => _MessageMediaBodyState();
}

class _MessageMediaBodyState extends State<MessageMediaBody>
    implements ChatNonTextBody {
  final Map<MediaItemId, AssetBinding> _bindings = {};
  final Map<MediaItemId, AssetPreset> _presets = {};
  final Map<MediaItemId, VoidCallback> _uploadListeners = {};
  final Map<MediaItemId, String> _uploadStates = {};
  AssetCacheScope? _scope;
  ChatSelectionController? _registeredWith;
  int? _registeredId;
  Object? _token;
  Duration? _lastAccepted;
  Offset? _lastQuery;
  MediaItemId? _hovered;
  Offset? _hoverAt;
  MouseCursor _cursor = MouseCursor.defer;
  bool _wasInSelection = false;
  final GlobalKey<LinkPreviewCardViewState> _cardKey = GlobalKey();

  MediaGesturePolicy get _gestures => widget.policy.gestures;

  MediaBlock$LinkPreview? get _cardBlock {
    for (final block in widget.layout.blocks) {
      if (block case final MediaBlock$LinkPreview card) return card;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    widget.state.attachOrigins(_rectOf);
    _register();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncBindings();
  }

  @override
  void didUpdateWidget(MessageMediaBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.state, widget.state)) {
      oldWidget.state.detachOrigins(_rectOf);
      widget.state.attachOrigins(_rectOf);
    }
    if (!identical(oldWidget.selection, widget.selection) ||
        oldWidget.messageId != widget.messageId) {
      _unregister();
      _register();
    }
    _syncBindings();
  }

  @override
  void dispose() {
    widget.state.detachOrigins(_rectOf);
    _unregister();
    _detachAll();
    super.dispose();
  }

  // --- Registration -------------------------------------------------------

  void _register() {
    final selection = widget.selection;
    final id = widget.messageId;
    if (selection == null || id == null) return;
    _registeredWith = selection;
    _registeredId = id;
    _token = selection.putNonTextBody(id, this);
    _wasInSelection = selection.isSelectionMode;
    selection
      ..addInteractionListener(_onInteraction)
      ..addListener(_onSelectionChanged);
  }

  void _unregister() {
    final selection = _registeredWith;
    final id = _registeredId;
    _registeredWith = null;
    _registeredId = null;
    if (selection == null || id == null) return;
    selection
      ..removeNonTextBody(id, token: _token)
      ..removeInteractionListener(_onInteraction)
      ..removeListener(_onSelectionChanged);
    _token = null;
  }

  // Entering or leaving message selection changes the cursor, the hover and
  // each node's action.
  // Only the mode matters here: a change of the selected set alone (a drag
  // over other rows) rebuilds nothing.
  void _onSelectionChanged() {
    if (!mounted || _inSelection == _wasInSelection) return;
    setState(() {
      _wasInSelection = _inSelection;
      _updateHover(_hoverAt);
    });
  }

  bool get _inSelection => widget.selection?.isSelectionMode ?? false;

  // --- Bindings -----------------------------------------------------------

  void _syncBindings() {
    final scope = ContentAssetProvider.maybeOf(context)?.media;
    if (!identical(scope, _scope)) {
      _detachAll();
      _scope = scope;
    }
    if (scope == null) return;
    final live = <MediaItemId>{};
    for (final (block, cell) in _cells) {
      final data = widget.dataOf(block, cell);
      if (data == null) continue;
      final id = cell.itemId;
      live.add(id);
      final preset = cell.kind.isPicture
          ? MediaBoxCell.presetFor(data)
          : MediaRowCell.presetOf(MediaRowCell.rowOf(context, data));
      if (_presets[id]?.spec == preset.spec && _bindings.containsKey(id)) {
        continue;
      }
      _detach(id);
      _presets[id] = preset;
      _watchUpload(
        id,
        _bindings[id] = scope.attach(
          data.item.descriptor.key.mediaKey,
          preset.spec,
          preset.profile,
          downloadContext: data.downloadContext,
        ),
      );
    }
    for (final id in _bindings.keys.toList()) {
      if (live.contains(id)) continue;
      _detach(id);
      _presets.remove(id);
    }
  }

  void _detach(MediaItemId id) {
    final binding = _bindings.remove(id);
    if (binding == null) return;
    if (_uploadListeners.remove(id) case final listener?) {
      binding.removeListener(listener);
    }
    _uploadStates.remove(id);
    binding.detach();
  }

  void _detachAll() {
    _bindings.keys.toList().forEach(_detach);
    _presets.clear();
  }

  // --- Uploads ------------------------------------------------------------

  void _watchUpload(MediaItemId id, AssetBinding binding) {
    void listener() => _onUpload(id, binding);
    _uploadListeners[id] = listener;
    binding.addListener(listener);
    _onUpload(id, binding);
  }

  // Reports a change of what the item's upload shows: sending, sent, then
  // none once the content is published. Bytes alone are no change.
  void _onUpload(MediaItemId id, AssetBinding binding) {
    final transfer = binding.transfer;
    final next = switch (transfer) {
      AssetTransfer$Sending() => 'sending',
      AssetTransfer$Sent() => 'sent',
      _ => null,
    };
    final last = _uploadStates[id];
    final state = next ?? (last == null ? null : 'none');
    if (state == null || state == last) return;
    if (next == null) {
      _uploadStates.remove(id);
    } else {
      _uploadStates[id] = next;
    }
    final correlation = widget.correlation;
    ChatDiagnostics.current.emit(
      ChatEventLevel.debug,
      ChatEventCategory.media,
      MediaOp.uploadState,
      correlation: ChatCorrelation(
        chatId: correlation.chatId,
        scrollId: correlation.scrollId,
        clientMessageId: correlation.clientMessageId,
        mediaItemId: id.toString(),
        mediaKey: binding.key.encoded,
      ),
      fields: () => {
        'state': state,
        if (transfer case AssetTransfer$Sending(:final sent, :final total)) ...{
          'sent': sent,
          'total': ?total,
        },
      },
    );
  }

  AssetLoadState _loadOf(MediaItemId id) => switch (_bindings[id]) {
    final binding? => AssetLoadState.of(binding),
    null => const AssetLoadState(stage: AssetStage.none),
  };

  // --- Geometry -----------------------------------------------------------

  Iterable<(MediaBlock, MediaCell)> get _cells sync* {
    for (final block in widget.layout.blocks) {
      for (final cell in block.cells) {
        yield (block, cell);
      }
    }
  }

  RenderBox? get _box => switch (context.findRenderObject()) {
    final RenderBox box when box.hasSize && box.attached => box,
    _ => null,
  };

  Rect _toGlobal(RenderBox box, Rect local) =>
      MatrixUtils.transformRect(box.getTransformTo(null), local);

  Rect? _rectOf(MediaItemId id) {
    final box = _box;
    if (box == null) return null;
    for (final (_, cell) in _cells) {
      if (cell.itemId == id) return _toGlobal(box, cell.rect);
    }
    return null;
  }

  bool _spoilerHidden(MediaItem item, MediaCell cell) =>
      MediaChromeSlots.spoilerRectOf(
        cell,
        item,
        revealed: widget.state.isSpoilerRevealed(item.id),
      ) !=
      null;

  /// The status control's rect of [cell], in layout coordinates, while it
  /// offers a download or a cancel; null otherwise.
  Rect? _statusRectOf(MediaBlock block, MediaCell cell) {
    if (widget.sendState == MediaSendState.failed) return null;
    final icon = _loadOf(cell.itemId).status().icon;
    if (icon != MediaStatusIcon.download && icon != MediaStatusIcon.cancel) {
      return null;
    }
    if (cell.kind.isPicture) {
      final diameter = MediaLoadingStyleScope.resolve(context).status.diameter;
      return Rect.fromCenter(
        center: cell.rect.center,
        width: diameter,
        height: diameter,
      );
    }
    final data = widget.dataOf(block, cell);
    if (data == null) return null;
    final row = MediaRowCell.rowOf(context, data);
    final leading = row.leading;
    final mirrored =
        row.mirrorsInRtl && Directionality.of(context) == TextDirection.rtl;
    final placed = mirrored
        ? Rect.fromLTWH(
            cell.rect.width - leading.right,
            leading.top,
            leading.width,
            leading.height,
          )
        : leading;
    return placed.shift(cell.rect.topLeft);
  }

  /// The part under [local] (layout coordinates) and its rect there.
  (MessageMediaHitPart, Rect)? _partAt(Offset local) {
    for (final (block, cell) in _cells) {
      final item = widget.items[cell.itemId];
      if (item == null) continue;
      final affordance = widget.policy.chrome.options.affordanceOf(
        cell,
        block,
        context: widget.chromeContext,
        spoilerHidden: _spoilerHidden(item, cell),
        smallImage: switch (block) {
          final MediaBlock$LinkPreview card => card.smallMedia,
          _ => false,
        },
      );
      if (affordance case final options? when options.hitRect.contains(local)) {
        return (
          MediaHitPart(item.id, part: MediaPart.options),
          options.hitRect,
        );
      }
    }
    for (final (block, cell) in _cells) {
      if (!cell.rect.contains(local)) continue;
      final item = widget.items[cell.itemId];
      if (item == null) return null;
      if (_spoilerHidden(item, cell)) {
        return (MediaHitPart(item.id, part: MediaPart.spoiler), cell.rect);
      }
      if (_statusRectOf(block, cell) case final status?
          when status.contains(local)) {
        return (MediaHitPart(item.id, part: MediaPart.status), status);
      }
      if (block case MediaBlock$LinkPreview(card: final card?)) {
        if (card.enlarge case final enlarge? when enlarge.contains(local)) {
          return (MediaHitPart(item.id, part: MediaPart.content), cell.rect);
        }
        // A photo in a card with text opens the page where the policy says
        // so (the enlarge button, where there is one, opens the viewer).
        if (card.hasText &&
            item.kind == MediaItemKind.photo &&
            widget.policy.linkPreview.photoTapOpensPage) {
          return switch (_cardPart(LinkPreviewZone.body)) {
            final part? => (part, card.rect),
            null => null,
          };
        }
      }
      return (MediaHitPart(item.id, part: MediaPart.content), cell.rect);
    }
    if (_cardBlock case MediaBlock$LinkPreview(
      card: final card?,
    ) when card.rect.contains(local)) {
      final zone = switch (card.button) {
        final button? when button.rect.contains(local) => (
          LinkPreviewZone.button,
          button.rect,
        ),
        _ => (LinkPreviewZone.body, card.rect),
      };
      return switch (_cardPart(zone.$1)) {
        final part? => (part, zone.$2),
        null => null,
      };
    }
    return null;
  }

  // A card part names its message: a body with no message id has no card
  // part, so nothing hits it and no tap reaches the host with a made-up id.
  LinkPreviewHitPart? _cardPart(LinkPreviewZone zone) =>
      switch (widget.messageId) {
        final id? => LinkPreviewHitPart(id, zone: zone),
        null => null,
      };

  // --- ChatNonTextBody ----------------------------------------------------

  @override
  Rect? get globalBounds => switch (_box) {
    final box? => _toGlobal(box, Offset.zero & box.size),
    null => null,
  };

  @override
  ChatInlineHit? inlineHitAt(Offset globalOffset) {
    final box = _box;
    final id = widget.messageId;
    if (box == null || id == null || !mounted) return null;
    _lastQuery = globalOffset;
    final local = box.globalToLocal(globalOffset);
    final found = _partAt(local);
    if (found == null) return null;
    final (part, rect) = found;
    // A link in the card's description is an ordinary text link.
    if (part case LinkPreviewHitPart(zone: LinkPreviewZone.body)) {
      if (_cardKey.currentState?.linkAt(local) case final link?) {
        return ChatInlineHit.link(
          messageId: id,
          title: link.title,
          url: link.url,
          contourPath: link.contour,
          touchOrigin: local,
        );
      }
    }
    return ChatInlineHit.bodyPart(
      messageId: id,
      partId: part,
      role: part.role,
      rect: _toGlobal(box, rect),
    );
  }

  // --- Actions ------------------------------------------------------------

  void _onInteraction(ChatSelectionInteraction interaction) {
    if (interaction case ChatBodyPartActivated(
      :final messageId,
      partId: final MediaHitPart part,
      :final rect,
    ) when messageId == widget.messageId && mounted) {
      if (widget.items.containsKey(part.itemId)) _activate(part, rect);
    }
    if (interaction case ChatBodyPartActivated(
      :final messageId,
      partId: final LinkPreviewHitPart part,
    ) when messageId == widget.messageId && mounted) {
      _activateCard(part);
    }
  }

  bool _accept(String part, MediaItemId? id) {
    final clock = widget.selection?.monotonicClock;
    if (clock == null) return true;
    final now = clock();
    final last = _lastAccepted;
    if (last != null && now - last < _gestures.activationGuard) {
      _emit(
        ChatEventLevel.debug,
        MediaOp.activationDropped,
        id,
        () => {'part': part, 'sinceMs': (now - last).inMilliseconds},
      );
      return false;
    }
    _lastAccepted = now;
    return true;
  }

  void _activateCard(LinkPreviewHitPart part) {
    final card = _cardBlock;
    if (card == null) return;
    if (!_accept(part.zone.name, null)) return;
    widget.onLinkPreview?.call(part, card.page);
    _emit(
      ChatEventLevel.debug,
      MediaOp.hit,
      null,
      () => {
        'part': part.zone.name,
        'role': part.role,
        'mode': 'normal',
        'outcome': switch (part.zone) {
          LinkPreviewZone.body => MediaHitOutcome.open,
          LinkPreviewZone.button => MediaHitOutcome.action,
        },
      },
    );
  }

  void _activate(MediaHitPart part, Rect? rect) {
    if (!_accept(part.part.name, part.itemId)) return;
    final id = part.itemId;
    switch (_gestures.actionOf(part.part, _loadOf(id))) {
      case MediaPartAction.reveal:
        widget.state.revealSpoiler(id, at: _revealOrigin(id));
        _emitOutcome(part, MediaHitOutcome.reveal);
      case MediaPartAction.download:
        _bindings[id]?.download();
      case MediaPartAction.cancel:
        final cross =
            part.part == MediaPart.status &&
            (widget.sendState == MediaSendState.sending ||
                _loadOf(id).status().upload);
        _bindings[id]?.cancelDownload();
        _emitOutcome(part, MediaHitOutcome.cancel);
        if (cross) _itemCancelled(id);
      case MediaPartAction.openViewer:
        _openViewer(id, rect);
      case MediaPartAction.none:
        break;
    }
  }

  // The cross on [id]: the owner heard the cancel through the binding; the
  // host hears the item, which leaves the message's list.
  void _itemCancelled(MediaItemId id) {
    final before = [
      for (final block in widget.layout.blocks)
        if (block case MediaBlock$Mosaic() || MediaBlock$FileStack())
          ...block.cells,
    ].length;
    _emit(
      ChatEventLevel.info,
      MediaOp.itemCancelled,
      id,
      () => {'albumBefore': before, 'albumAfter': before - 1},
    );
    widget.onItemCancelled?.call(id);
  }

  // Where the reveal starts in the item's cell: the point the tap's hit was
  // read at, when it lies in the cell.
  Offset? _revealOrigin(MediaItemId id) {
    final box = _box;
    final query = _lastQuery;
    if (box == null || query == null) return null;
    final local = box.globalToLocal(query);
    for (final (_, cell) in _cells) {
      if (cell.itemId == id && cell.rect.contains(local)) {
        return local - cell.rect.topLeft;
      }
    }
    return null;
  }

  void _openViewer(MediaItemId id, Rect? rect) {
    final open = widget.onOpenViewer;
    final messageId = widget.messageId;
    if (open == null || messageId == null) return;
    final item = widget.items[id];
    if (item == null) return;
    final boxes = item.kind.isPicture;
    // A message's pictures page together; a file opens alone.
    final pages = boxes
        ? [
            for (final (_, cell) in _cells)
              if (cell.kind.isPicture) cell.itemId,
          ]
        : [id];
    final index = pages.indexOf(id);
    if (rect == null) {
      _emit(
        ChatEventLevel.warning,
        MediaOp.originRectMissing,
        id,
        () => {'at': MediaViewerMoment.open},
      );
    }
    _emit(
      ChatEventLevel.info,
      MediaOp.viewerOpened,
      id,
      () => {'index': index, 'count': pages.length},
    );
    final state = widget.state;
    final correlation = widget.correlation;
    open(
      MediaViewerRequest(
        messageId: messageId,
        items: List.unmodifiable(pages),
        index: index,
        originRect: rect,
        rectOf: (id) {
          final found = state.rectOf(id);
          if (found == null) {
            _emitWith(
              correlation,
              ChatEventLevel.warning,
              MediaOp.originRectMissing,
              id,
              () => {'at': MediaViewerMoment.close},
            );
          }
          return found;
        },
      ),
    );
  }

  void _emitOutcome(MediaHitPart part, MediaHitOutcome outcome) => _emit(
    ChatEventLevel.debug,
    MediaOp.hit,
    part.itemId,
    () => {
      'part': part.part.name,
      'role': part.role,
      'mode': 'normal',
      'outcome': outcome,
    },
  );

  void _emit(
    ChatEventLevel level,
    MediaOp op,
    MediaItemId? id,
    Map<String, Object> Function() fields,
  ) => _emitWith(widget.correlation, level, op, id, fields);

  static void _emitWith(
    ChatCorrelation correlation,
    ChatEventLevel level,
    MediaOp op,
    MediaItemId? id,
    Map<String, Object> Function() fields,
  ) => ChatDiagnostics.current.emit(
    level,
    ChatEventCategory.media,
    op,
    correlation: ChatCorrelation(
      chatId: correlation.chatId,
      scrollId: correlation.scrollId,
      clientMessageId: correlation.clientMessageId,
      mediaItemId: id?.toString(),
    ),
    fields: fields,
  );

  // --- Mouse --------------------------------------------------------------

  void _updateHover(Offset? global) {
    _hoverAt = global;
    final box = _box;
    final found = global == null || box == null || _inSelection
        ? null
        : _partAt(box.globalToLocal(global));
    _hovered = switch (found?.$1) {
      MediaHitPart(:final itemId) => itemId,
      _ => null,
    };
    _cursor = found != null && _gestures.clickCursor
        ? SystemMouseCursors.click
        : MouseCursor.defer;
  }

  void _onHover(PointerHoverEvent event) {
    final hovered = _hovered;
    final cursor = _cursor;
    _updateHover(event.position);
    if (hovered != _hovered || cursor != _cursor) setState(() {});
  }

  void _onExit(PointerExitEvent event) {
    if (_hovered == null && _cursor == MouseCursor.defer) return;
    setState(() => _updateHover(null));
  }

  // --- Semantics ----------------------------------------------------------

  Widget _node(MediaBlock block, MediaCell cell, Widget child) {
    final item = widget.items[cell.itemId];
    if (item == null) return child;
    final binding = _bindings[item.id];
    Widget build(AssetLoadState load) =>
        _semantics(block, cell, item, load, child);
    if (binding == null) {
      return build(const AssetLoadState(stage: AssetStage.none));
    }
    return AssetLoadStateBuilder.binding(
      binding,
      builder: (context, load, _) => build(load),
    );
  }

  Widget _semantics(
    MediaBlock block,
    MediaCell cell,
    MediaItem item,
    AssetLoadState load,
    Widget child,
  ) {
    final strings = ChromeStringsScope.mediaOf(context);
    final descriptor = item.descriptor;
    final box = item.kind.isPicture;
    final label = strings.label(
      kind: item.kind,
      duration: item.kind.plays ? descriptor.duration : null,
      size: !box || !load.shown
          ? descriptor.byteSize ?? _bindings[item.id]?.descriptor?.byteSize
          : null,
      loading: load.loading,
      fraction: load.fraction,
    );
    final selection = widget.selection;
    final messageId = widget.messageId;
    if (_inSelection && selection != null && messageId != null) {
      return Semantics(
        container: true,
        label: label,
        onTap: selection.isSelectable(messageId)
            ? () => selection.toggle(messageId)
            : null,
        child: ExcludeSemantics(child: child),
      );
    }
    final hidden = _spoilerHidden(item, cell);
    final icon = widget.sendState == MediaSendState.failed
        ? MediaStatusIcon.none
        : load.status().icon;
    final affordance = widget.policy.chrome.options.affordanceOf(
      cell,
      block,
      context: widget.chromeContext,
      spoilerHidden: hidden,
    );
    final onItemMenu = widget.onItemMenu;
    return Semantics(
      container: true,
      label: label,
      onTap: () => _activate(
        MediaHitPart(
          item.id,
          part: hidden ? MediaPart.spoiler : MediaPart.content,
        ),
        _rectOf(item.id),
      ),
      customSemanticsActions: {
        if (!hidden &&
            (icon == MediaStatusIcon.download ||
                icon == MediaStatusIcon.cancel))
          CustomSemanticsAction(
            label: icon == MediaStatusIcon.download
                ? strings.downloadAction
                : strings.cancelDownloadAction,
          ): () => _activate(
            MediaHitPart(item.id, part: MediaPart.status),
            _rectOf(item.id),
          ),
        if (affordance != null && onItemMenu != null)
          CustomSemanticsAction(label: strings.optionsAction): () {
            if (_box case final box?) {
              onItemMenu(
                MediaHitPart(item.id, part: MediaPart.options),
                _toGlobal(box, affordance.hitRect),
              );
            }
          },
      },
      child: ExcludeSemantics(child: child),
    );
  }

  // --- Build --------------------------------------------------------------

  Widget _hover(MediaCell cell, Widget child) {
    final look = _gestures.hover;
    if (look == null || widget.selection == null) return child;
    final radii = cell.radii;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: _hovered == cell.itemId ? 1 : 0,
              duration: look.duration,
              child: ClipRRect(
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(radii.topLeft),
                  topRight: Radius.circular(radii.topRight),
                  bottomLeft: Radius.circular(radii.bottomLeft),
                  bottomRight: Radius.circular(radii.bottomRight),
                ),
                child: ColoredBox(color: look.color),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _decorate(MediaBlock block, MediaCell cell, Widget built) =>
      _node(block, cell, _hover(cell, built));

  @override
  Widget build(BuildContext context) {
    final stack = Stack(
      clipBehavior: Clip.none,
      children: [
        for (final (block, cell) in _cells)
          if (block case MediaBlock$Mosaic() || MediaBlock$FileStack())
            widget.cellBuilder(context, block, cell, _decorate),
        if (_cardBlock
            case final MediaBlock$LinkPreview block &&
                MediaBlock$LinkPreview(card: final card?))
          _card(context, block, card),
        if (widget.leavingCard
            case final MediaBlock$LinkPreview block &&
                MediaBlock$LinkPreview(card: final card?))
          Positioned.fromRect(
            rect: card.rect,
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: Opacity(
                  opacity: widget.leavingCardOpacity,
                  child: LinkPreviewCardView(
                    block: block,
                    card: card,
                    policy: widget.policy.linkPreview,
                    colors: widget.linkPreviewColors,
                    pressable: false,
                  ),
                ),
              ),
            ),
          ),
        // A cell on its way out is no part any more: drawn bare.
        for (final cell in widget.layout.exiting)
          widget.cellBuilder(
            context,
            cell.kind.isPicture
                ? MediaBlock.mosaic(rect: cell.rect, cells: [cell])
                : MediaBlock.fileStack(rect: cell.rect, cells: [cell]),
            cell,
            _bare,
          ),
      ],
    );
    if (widget.selection == null) return stack;
    return MouseRegion(
      cursor: _cursor,
      opaque: false,
      onHover: _onHover,
      onExit: _onExit,
      child: stack,
    );
  }

  static Widget _bare(MediaBlock block, MediaCell cell, Widget built) => built;

  // --- Link preview card --------------------------------------------------

  Widget _card(
    BuildContext context,
    MediaBlock$LinkPreview block,
    LinkPreviewCard card,
  ) {
    final page = block.page;
    final strings = ChromeStringsScope.mediaOf(context);
    final selection = widget.selection;
    final messageId = widget.messageId;
    final inSelection = _inSelection && selection != null && messageId != null;
    VoidCallback? tapOf(LinkPreviewZone zone) => switch (selection) {
      final selection? when inSelection =>
        selection.isSelectable(messageId)
            ? () => selection.toggle(messageId)
            : null,
      _ => switch (_cardPart(zone)) {
        final part? => () => _activateCard(part),
        null => null,
      },
    };
    final media = switch (block.media) {
      final cell? => widget.cellBuilder(
        context,
        block,
        cell,
        _decorate,
        origin: card.rect.topLeft,
      ),
      null => null,
    };
    final view = LinkPreviewCardView(
      key: _cardKey,
      block: block,
      card: card,
      policy: widget.policy.linkPreview,
      colors: widget.linkPreviewColors,
      media: media,
      pressable: !_inSelection,
      correlation: widget.correlation,
    );
    return Positioned.fromRect(
      key: const ValueKey('linkPreviewCard'),
      rect: card.rect,
      child: Opacity(
        opacity: widget.cardOpacity,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: Semantics(
                container: true,
                label: strings.cardLabel(
                  title: page.title,
                  text: page.description.plain,
                ),
                onTap: tapOf(LinkPreviewZone.body),
              ),
            ),
            view,
            if (card.button case final button?)
              Positioned.fromRect(
                rect: button.rect.shift(-card.rect.topLeft),
                child: Semantics(
                  container: true,
                  button: true,
                  label: button.label,
                  onTap: tapOf(LinkPreviewZone.button),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
