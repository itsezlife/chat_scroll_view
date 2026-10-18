import 'package:catalog_assets/catalog_assets.dart';
import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:flutter/widgets.dart';

/// Holds the chat's animations still while a route is open over it.
///
/// The reference desktop client pauses the chat under any box layer. Flutter's
/// `TickerMode` does not: it only reaches the routes beneath an opaque one, so
/// a dialog or a sheet leaves the chat animating behind its barrier. This
/// observer asks a `PlaybackActivity` for one `holdOverlay` per modal route
/// pushed above the first (the chat itself) and gives each back when the route
/// leaves, however it leaves. Holds count, so a sheet over a dialog keeps the
/// pause until both are gone.
///
/// It treats every `ModalRoute` the same, pickers included, except the message
/// menu: that one keeps the message it opens on in view, so the chat goes on
/// playing under it. The example opens no other menu as a route; a host with
/// more filters on the route before holding.
final class PlaybackOverlayPauseObserver extends NavigatorObserver {
  /// Creates an observer that holds overlays on [activity].
  PlaybackOverlayPauseObserver(this._activity);

  final PlaybackActivity _activity;
  final Map<Route<dynamic>, PlaybackOverlayHold> _holds =
      Map<Route<dynamic>, PlaybackOverlayHold>.identity();

  void _hold(Route<dynamic> route) {
    if (route is! ModalRoute<dynamic> || route.isFirst) return;
    if (route.settings.name == ChatMessageMenu.routeName) return;
    _holds.putIfAbsent(route, _activity.holdOverlay);
  }

  void _release(Route<dynamic> route) => _holds.remove(route)?.release();

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _hold(route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _release(route);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _release(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (oldRoute != null) _release(oldRoute);
    if (newRoute != null) _hold(newRoute);
  }

  /// Gives back every claim still open. Idempotent.
  void dispose() {
    for (final hold in _holds.values.toList()) {
      hold.release();
    }
    _holds.clear();
  }
}
