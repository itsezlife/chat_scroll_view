import 'dart:ui' as ui show Image;

import 'package:chrome_foundation/chrome_foundation.dart' show ChromeTextRoot;
import 'package:content_assets/content_assets.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:listen/listen.dart' as listen;
import 'package:message_media/message_media.dart';
import 'package:mpx_core/mpx_core.dart';
import 'package:mpx_player/mpx_player.dart' show PlayerPool;
import 'package:mpx_ui/mpx_ui.dart';

/// What a chat's media bubbles take from the chat screen: the platform's
/// message media policy, the receiver's link preview lookups, and where a
/// tap on an item, a card or an item's options goes.
///
/// One per chat screen, created and disposed with it (ADR 029: per-chat
/// controllers).
final class ChatMediaHost {
  /// The media of the chat [chatId], laid out by [policy] (the running
  /// platform's by default); [resolver] looks up the link previews a
  /// received message names without a page.
  ChatMediaHost({
    required this.chatId,
    required this.resolver,
    MessageMediaPolicy? policy,
    this.downloadContext,
    this.onOpenViewer,
    this.onItemMenu,
    this.onLinkPreview,
  }) : policy = policy ?? MessageMediaPolicy.platform();

  /// The chat the media's events name.
  final String chatId;

  /// How every media bubble of the chat is laid out and painted.
  final MessageMediaPolicy policy;

  /// Looks up a received message's link preview when it came without a
  /// page.
  final LinkPreviewResolver resolver;

  /// The class of the conversation the media shows in.
  final AutoDownloadContext? downloadContext;

  /// Opens the viewer on a tap on an item: the request and the message's
  /// items, which hold what the request names by id.
  final void Function(
    BuildContext context,
    MediaViewerRequest request,
    List<MediaItem> items,
  )?
  onOpenViewer;

  /// The options affordance's semantics action on an item of a message.
  final void Function(
    BuildContext context,
    int messageId,
    MediaHitPart part,
    Rect rect,
  )?
  onItemMenu;

  /// A tap on a link preview card of a message.
  final void Function(int messageId, LinkPreviewHitPart part, LinkPreview page)?
  onLinkPreview;

  final Map<int, LinkPreviewRequest> _lookups = {};
  bool _disposed = false;

  /// The lookup of [candidates] for the message [messageId]: one per
  /// message while the screen is open, so a bubble that scrolls away and
  /// back does not ask again.
  LinkPreviewRequest lookUp(int messageId, List<Uri> candidates) {
    assert(!_disposed, 'The media host is disposed.');
    return _lookups[messageId] ??= resolver.resolve(candidates);
  }

  /// Cancels the lookups still pending.
  void dispose() {
    _disposed = true;
    for (final request in _lookups.values) {
      request.cancel();
    }
    _lookups.clear();
  }
}

/// What the chat's viewer chrome says about a message: its sender, its
/// date, its caption, and the actions of each item.
@immutable
final class ChatViewerDetails {
  /// The details of one message's media.
  const ChatViewerDetails({
    required this.title,
    this.subtitle,
    this.caption,
    this.actionsOf,
  });

  /// The title (the sender).
  final String title;

  /// The line under the title (the date).
  final String? subtitle;

  /// The message's caption, under the picture; null for none.
  final String? caption;

  /// The actions of [item]; none when null.
  final List<ViewerAction> Function(MediaItem item)? actionsOf;
}

/// An action the chat's viewer offers on an item.
enum ChatViewerAction {
  /// Forward the message the item is in.
  forward,

  /// Delete the message the item is in.
  delete,

  /// Save the item where its kind's save entry saves.
  save,

  /// Share the item out of the chat.
  share,
}

/// The media viewer over a message's items: opens from the tapped item's
/// rect and closes to the rect the shown item has then, hiding the item it
/// shows in the chat; plays videos on the host's players and draws the
/// host's chrome.
abstract final class ChatMediaViewer {
  /// Whether [request] names a picture the viewer shows (a file alone is
  /// not one).
  static bool shows(MediaViewerRequest request, List<MediaItem> items) =>
      galleryOf(request, items).isNotEmpty;

  /// The items of [request] the viewer pages through, in order: its
  /// pictures (photos, videos, animations).
  static List<MediaItem> shownOf(
    MediaViewerRequest request,
    List<MediaItem> items,
  ) {
    final byId = {for (final item in items) item.id: item};
    return [
      for (final id in request.items) ?byId[id],
    ].where((item) => _kindOf(item.kind) != null).toList();
  }

  /// The gallery of [request]: its items in order, each a picture with its
  /// media key and size.
  static List<GalleryItem> galleryOf(
    MediaViewerRequest request,
    List<MediaItem> items, {
    AutoDownloadContext? downloadContext,
  }) => [
    for (final item in shownOf(request, items))
      GalleryItem(
        item.descriptor.key.mediaKey,
        kind: _kindOf(item.kind)!,
        size: switch (item.descriptor.size) {
          final size? => Size(size.width.toDouble(), size.height.toDouble()),
          null => null,
        },
        hasAudio: false,
        descriptor: item.descriptor.mediaDescriptor,
        downloadContext: downloadContext,
      ),
  ];

  static GalleryMediaKind? _kindOf(MediaItemKind kind) => switch (kind) {
    MediaItemKind.photo => GalleryMediaKind.photo,
    MediaItemKind.video => GalleryMediaKind.video,
    MediaItemKind.animation => GalleryMediaKind.animation,
    _ => null,
  };

  /// The viewer's link to the chat for [request]: each page's origin by its
  /// item's id, and the item it shows hidden and covered in the chat's
  /// [state] (by id, so the hidden cell follows the page); without a state
  /// the chat keeps drawing it.
  static OriginBridge bridgeOf(
    MediaViewerRequest request,
    List<MediaItem> items, {
    MessageMediaState? state,
  }) => _RequestOrigins(request, [
    for (final item in shownOf(request, items)) item.id,
  ], state);

  /// The viewer's actions on [item]: Forward and Delete in the bar where
  /// the chat allows them ([canForward], [canDelete]), then the save entry
  /// saying [saveLabel] (none when null: protection denies the save) and
  /// Share where [allowed] (the item's `MediaItemAction.allowedItemActions`)
  /// has it, in the menu. Each reaches [onAction] with the item.
  static List<ViewerAction> actionsFor(
    MediaItem item, {
    required Set<MediaItemAction> allowed,
    required bool canForward,
    required bool canDelete,
    required void Function(MediaItem item, ChatViewerAction action) onAction,
    String? saveLabel,
  }) {
    ViewerAction of(ChatViewerAction action, String label, IconData icon) =>
        ViewerAction(
          label: label,
          icon: Icon(icon),
          inBar:
              action == ChatViewerAction.forward ||
              action == ChatViewerAction.delete,
          onSelected: (_) => onAction(item, action),
        );
    return [
      if (canForward)
        of(ChatViewerAction.forward, 'Forward', Icons.forward_outlined),
      if (canDelete)
        of(ChatViewerAction.delete, 'Delete', Icons.delete_outline),
      if (saveLabel case final label?)
        of(ChatViewerAction.save, label, Icons.download_outlined),
      if (allowed.contains(MediaItemAction.share))
        of(ChatViewerAction.share, 'Share', Icons.share_outlined),
    ];
  }

  /// Pushes the viewer on [request]'s items over [context]'s navigator, its
  /// page under a chrome text root.
  ///
  /// Videos play on [players] (a still without them); [details] fill the
  /// bars, the caption and the actions, and an album shows the strip of its
  /// pictures; [state] is the chat's media state the viewer hides its item
  /// in.
  ///
  /// The viewer asks [details] for an item's actions each time its chrome
  /// builds, which a change of the chat's protection does not cause: the
  /// page builds the chrome again when [changes] notifies, so an action
  /// protection takes away leaves the open viewer (its menu too), keeping
  /// the page and the hidden cell as they are.
  static Future<void> open(
    BuildContext context,
    MediaViewerRequest request,
    List<MediaItem> items, {
    AutoDownloadContext? downloadContext,
    PlayerPool? players,
    ChatViewerDetails? details,
    MessageMediaState? state,
    listen.Listenable? changes,
  }) {
    final shown = shownOf(request, items);
    if (shown.isEmpty) return Future.value();
    final gallery = galleryOf(request, items, downloadContext: downloadContext);
    final index = shown
        .indexWhere((item) => item.id == request.item)
        .clamp(0, shown.length - 1);
    final scope = AssetCacheProvider.maybeOf(context);
    final policy = ViewerPolicyScope.resolve(context);
    final source = _ListGallery(gallery);
    final bridge = bridgeOf(request, items, state: state);
    final chrome = switch (details) {
      final details? => _chromeOf(details, shown),
      null => null,
    };
    return Navigator.of(context).push<void>(
      PageRouteBuilder<void>(
        opaque: false,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (routeContext, _, _) => ChromeTextRoot(
          child: _LiveViewer(
            changes: changes,
            // The source and the bridge are made once: a viewer handed new
            // ones reloads its pages and moves the chat's hidden cell.
            builder: () => MediaViewer(
              source: source,
              initialIndex: index,
              bridge: bridge,
              policy: policy,
              scope: scope,
              players: players,
              chrome: chrome,
              onClosed: () => Navigator.of(routeContext).pop(),
            ),
          ),
        ),
      ),
    );
  }

  static ViewerChrome _chromeOf(
    ChatViewerDetails details,
    List<MediaItem> shown,
  ) => ViewerChrome(
    title: (context, index, item) => Text(details.title),
    subtitle: switch (details.subtitle) {
      final subtitle? => (context, index, item) => Text(subtitle),
      null => null,
    },
    caption: switch (details.caption) {
      final caption? when caption.isNotEmpty => (context, index, item) => Text(
        caption,
      ),
      _ => null,
    },
    thumbnails: shown.length > 1,
    actions: switch (details.actionsOf) {
      final actionsOf? => (index, item) => actionsOf(shown[index]),
      null => null,
    },
  );
}

// Builds the viewer again whenever [changes] notifies, so its chrome asks
// for the actions again; without changes it builds once.
final class _LiveViewer extends StatefulWidget {
  const _LiveViewer({required this.changes, required this.builder});

  final listen.Listenable? changes;
  final MediaViewer Function() builder;

  @override
  State<_LiveViewer> createState() => _LiveViewerState();
}

final class _LiveViewerState extends State<_LiveViewer> {
  @override
  void initState() {
    super.initState();
    widget.changes?.addListener(_changed);
  }

  @override
  void didUpdateWidget(_LiveViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(widget.changes, oldWidget.changes)) return;
    oldWidget.changes?.removeListener(_changed);
    widget.changes?.addListener(_changed);
  }

  @override
  void dispose() {
    widget.changes?.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => widget.builder();
}

final class _ListGallery implements GallerySource {
  const _ListGallery(this._items);

  final List<GalleryItem> _items;

  @override
  int get count => _items.length;

  @override
  GalleryItem? itemAt(int index) => _items[index];

  @override
  void loadAround(int index) {}

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}

// The viewer's origins from the request: each item's rect by id as the chat
// shows it now (its mounted views answer, so a row rebuilt while the viewer
// was up still does), the tapped item's rect at the tap when its row is
// gone. The item the viewer shows is hidden and covered in the chat's media
// state by its id.
final class _RequestOrigins implements OriginBridge {
  const _RequestOrigins(this._request, this._ids, this._state);

  final MediaViewerRequest _request;
  final List<MediaItemId> _ids;
  final MessageMediaState? _state;

  @override
  GalleryOrigin? originOf(int index) {
    final id = _ids[index];
    final rect = switch (_request.rectOf(id)) {
      final fresh? => fresh,
      null when id == _request.item => _request.originRect,
      null => null,
    };
    return switch (rect) {
      final rect? => GalleryOrigin(rect: rect),
      null => null,
    };
  }

  @override
  Future<void> reveal(int index) => Future.value();

  @override
  void setCovered(int index, {required bool covered}) =>
      _state?.setViewerCovered(_ids[index], covered: covered);

  @override
  void setHidden(int index, {required bool hidden}) =>
      _state?.setViewerHidden(_ids[index], hidden: hidden);

  @override
  void handBack(int index, Duration position) {}

  @override
  ui.Image? frameOf(int index) => null;
}
