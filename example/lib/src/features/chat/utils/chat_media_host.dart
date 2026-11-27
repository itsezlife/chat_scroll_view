import 'dart:ui' as ui show Image;

import 'package:chrome_foundation/chrome_foundation.dart' show ChromeTextRoot;
import 'package:content_assets/content_assets.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/widgets.dart';
import 'package:message_media/message_media.dart';
import 'package:mpx_core/mpx_core.dart';
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

/// The media viewer over a message's items: opens from the tapped item's
/// rect and closes to the rect the shown item has then.
abstract final class ChatMediaViewer {
  /// Whether [request] names a picture the viewer shows (a file alone is
  /// not one).
  static bool shows(MediaViewerRequest request, List<MediaItem> items) =>
      galleryOf(request, items).isNotEmpty;

  /// The gallery of [request]: its items in order, each a picture with its
  /// media key and size.
  static List<GalleryItem> galleryOf(
    MediaViewerRequest request,
    List<MediaItem> items, {
    AutoDownloadContext? downloadContext,
  }) {
    final byId = {for (final item in items) item.id: item};
    return [
      for (final id in request.items)
        if (byId[id] case final item?)
          if (_kindOf(item.kind) case final kind?)
            GalleryItem(
              item.descriptor.key.mediaKey,
              kind: kind,
              size: switch (item.descriptor.size) {
                final size? => Size(
                  size.width.toDouble(),
                  size.height.toDouble(),
                ),
                null => null,
              },
              hasAudio: false,
              descriptor: item.descriptor.mediaDescriptor,
              downloadContext: downloadContext,
            ),
    ];
  }

  static GalleryMediaKind? _kindOf(MediaItemKind kind) => switch (kind) {
    MediaItemKind.photo => GalleryMediaKind.photo,
    MediaItemKind.video => GalleryMediaKind.video,
    MediaItemKind.animation => GalleryMediaKind.animation,
    _ => null,
  };

  /// Pushes the viewer on [request]'s items over [context]'s navigator, its
  /// page under a chrome text root.
  static Future<void> open(
    BuildContext context,
    MediaViewerRequest request,
    List<MediaItem> items, {
    AutoDownloadContext? downloadContext,
  }) {
    final gallery = galleryOf(request, items, downloadContext: downloadContext);
    if (gallery.isEmpty) return Future.value();
    final shown = [
      for (final id in request.items)
        if (items.any((item) => item.id == id && _kindOf(item.kind) != null))
          id,
    ];
    final index = shown.indexOf(request.item).clamp(0, shown.length - 1);
    final scope = AssetCacheProvider.maybeOf(context);
    final policy = ViewerPolicyScope.resolve(context);
    return Navigator.of(context).push<void>(
      PageRouteBuilder<void>(
        opaque: false,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (routeContext, _, _) => ChromeTextRoot(
          child: MediaViewer(
            source: _ListGallery(gallery),
            initialIndex: index,
            bridge: _RequestOrigins(request, shown),
            policy: policy,
            scope: scope,
            onClosed: () => Navigator.of(routeContext).pop(),
          ),
        ),
      ),
    );
  }
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
// gone.
final class _RequestOrigins implements OriginBridge {
  const _RequestOrigins(this._request, this._ids);

  final MediaViewerRequest _request;
  final List<MediaItemId> _ids;

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
  void setCovered(int index, {required bool covered}) {}

  @override
  void setHidden(int index, {required bool hidden}) {}

  @override
  void handBack(int index, Duration position) {}

  @override
  ui.Image? frameOf(int index) => null;
}
