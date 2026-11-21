import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:panel_catalog/src/viewport/panel_catalog_controller.dart';
import 'package:panel_catalog/src/viewport/panel_catalog_scroll_events.dart';
import 'package:viewport_scroll/viewport_scroll.dart';

/// The catalogue as a `FastScrollTarget`: its [controller]'s offset over
/// its scroll range, its viewport over its content.
///
/// It notifies on each event the controller publishes (moves, flings, jumps,
/// the section reached). The catalogue publishes no event for a change of
/// length alone (a new snapshot that leaves the offset where it was), so a
/// scrollbar over it catches up on the next move.
///
/// Adapters on one controller share their listeners and are equal, so a
/// widget rebuilt with a new adapter keeps them; the controller's events
/// are listened to while any adapter has a listener.
@immutable
final class PanelCatalogFastScrollTarget extends FastScrollTarget {
  /// The target of [controller].
  const PanelCatalogFastScrollTarget(this.controller);

  /// The controller moved.
  final PanelCatalogController controller;

  static final _hubs = Expando<_Listeners>('PanelCatalogFastScrollTarget');

  _Listeners get _hub => _hubs[controller] ??= _Listeners(controller);

  @override
  double? get progress {
    final max = controller.maxScrollExtent;
    if (!controller.hasPosition || max <= 0) return null;
    return (controller.offset / max).clamp(0.0, 1.0);
  }

  @override
  double get visibleShare {
    final content = controller.contentExtent;
    final viewport = controller.viewportExtent;
    if (content <= 0 || viewport <= 0 || viewport >= content) return 1;
    return viewport / content;
  }

  @override
  void jumpTo(double progress) {
    final max = controller.maxScrollExtent;
    if (!controller.hasPosition || max <= 0) return;
    controller.jumpTo(progress.clamp(0.0, 1.0) * max);
  }

  // A jump to where it is ends a fling or a programmatic motion.
  @override
  void stop() => controller.jumpTo(controller.offset);

  @override
  void addListener(VoidCallback listener) => _hub.add(listener);

  @override
  void removeListener(VoidCallback listener) => _hub.remove(listener);

  @override
  bool operator ==(Object other) =>
      other is PanelCatalogFastScrollTarget &&
      identical(other.controller, controller);

  @override
  int get hashCode => identityHashCode(controller);
}

/// The listeners of every adapter on one controller, and the one
/// subscription to its events they need while there are any.
final class _Listeners {
  _Listeners(this._controller);

  final PanelCatalogController _controller;
  final List<VoidCallback> _listeners = [];
  StreamSubscription<PanelCatalogScrollEvent>? _events;

  void add(VoidCallback listener) {
    _listeners.add(listener);
    _events ??= _controller.events.listen((_) => _notify());
  }

  void remove(VoidCallback listener) {
    _listeners.remove(listener);
    if (_listeners.isNotEmpty) return;
    unawaited(_events?.cancel());
    _events = null;
  }

  void _notify() {
    for (final listener in List<VoidCallback>.of(_listeners)) {
      listener();
    }
  }
}
