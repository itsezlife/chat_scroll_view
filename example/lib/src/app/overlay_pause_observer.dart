import 'package:catalog_assets/catalog_assets.dart';
import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:flutter/widgets.dart';
import 'package:panel_pages/panel_pages.dart';

/// Holds the chat's animations still while a route is open over it.
///
/// The chat pauses under any box layer. Flutter's
/// `TickerMode` does not: it only reaches the routes beneath an opaque one, so
/// a dialog or a sheet leaves the chat animating behind its barrier. This
/// observer asks a `PlaybackActivity` for one `holdOverlay` per modal route
/// pushed above the first (the chat itself) and gives each back when the route
/// leaves, however it leaves. Holds count, so a sheet over a dialog keeps the
/// pause until both are gone.
///
/// It treats every `ModalRoute` the same, pickers included, except two:
///
/// - the message menu keeps the message it opens on in view, so the chat goes
///   on playing under it;
/// - a pack sheet (`PackSheet.routeName`) plays its own stickers and emoji,
///   and the preview opened from it, so the clock is held only while the
///   sheet moves in or out: every animation is paused for its open and
///   close. While it is open the opener holds the
///   chat under it on its own (`PanelPlaybackHold.holdChat`): one clock serves
///   both, so pausing the chat must not pause the sheet.
///
/// The example opens no other menu as a route; a host with more filters on
/// the route before holding.
///
/// ## When the chat is itself a pushed page
///
/// "Above the first route" only means "over the chat" when the chat is the
/// first route. A chat opened from a list is pushed over the list: without
/// help the observer would take the chat for an overlay over itself and hold
/// its animations still for as long as it is open. [isChat] names the route
/// that is the chat; it is never held, and what is opened over it is.
final class PlaybackOverlayPauseObserver extends NavigatorObserver {
  /// Creates an observer that holds overlays on [activity].
  ///
  /// [isChat] says which route is the chat itself, for a host that pushes it.
  PlaybackOverlayPauseObserver(
    this._activity, {
    bool Function(Route<dynamic> route) isChat = _never,
  }) : _isChat = isChat;

  static bool _never(Route<dynamic> route) => false;

  final PlaybackActivity _activity;
  final bool Function(Route<dynamic> route) _isChat;
  final Map<Route<dynamic>, PlaybackOverlayHold> _holds =
      Map<Route<dynamic>, PlaybackOverlayHold>.identity();
  final Map<Route<dynamic>, _MotionHold> _motions =
      Map<Route<dynamic>, _MotionHold>.identity();

  void _hold(Route<dynamic> route) {
    if (route is! ModalRoute<dynamic> || route.isFirst || _isChat(route)) {
      return;
    }
    switch (route.settings.name) {
      case ChatMessageMenu.routeName:
        return;
      case PackSheet.routeName:
        final animation = route.animation;
        if (animation == null || _motions.containsKey(route)) return;
        final motion = _motions[route] = _MotionHold(animation, _activity);
        motion.follow(onDone: () => _motions.remove(route));
        return;
    }
    _holds.putIfAbsent(route, _activity.holdOverlay);
  }

  // A pack sheet's motion hold is not ended by its pop: the pop starts the
  // close, which it holds through to the end.
  void _release(Route<dynamic> route) => _holds.remove(route)?.release();

  void _remove(Route<dynamic> route) {
    _release(route);
    _motions.remove(route)?.dispose();
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _hold(route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _release(route);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _remove(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (oldRoute != null) _remove(oldRoute);
    if (newRoute != null) _hold(newRoute);
  }

  /// Gives back every claim still open. Idempotent.
  void dispose() {
    for (final hold in _holds.values.toList()) {
      hold.release();
    }
    _holds.clear();
    for (final motion in _motions.values.toList()) {
      motion.dispose();
    }
    _motions.clear();
  }
}

/// Holds the overlay layer while a route's transition runs: from its push
/// until it is open, and from its pop until it is gone.
final class _MotionHold {
  _MotionHold(this._animation, this._activity);

  final Animation<double> _animation;
  final PlaybackActivity _activity;

  PlaybackOverlayHold? _hold;
  VoidCallback? _onDone;

  /// Starts following the transition; [onDone] runs once the route is gone
  /// (its transition dismissed).
  void follow({required VoidCallback onDone}) {
    _onDone = onDone;
    _animation.addStatusListener(_follow);
    _follow(_animation.status);
  }

  void _follow(AnimationStatus status) {
    if (status.isAnimating) {
      _hold ??= _activity.holdOverlay();
      return;
    }
    _hold?.release();
    _hold = null;
    if (status.isDismissed) {
      final onDone = _onDone;
      dispose();
      onDone?.call();
    }
  }

  /// Stops following and gives the hold back. Idempotent.
  void dispose() {
    _onDone = null;
    _animation.removeStatusListener(_follow);
    _hold?.release();
    _hold = null;
  }
}
