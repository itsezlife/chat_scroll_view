import 'package:flutter/foundation.dart';

/// The three facts that decide whether background baking may run, as small
/// signals the host owns and updates: baking never competes with something
/// the user is looking at or touching.
///
/// Baking runs only while the panel is visible, nothing is scrolling and the
/// panel is not animating open. Wiring each signal to the real viewport and
/// panel is the host's job; this type only reads them.
final class BakePauseSignals {
  /// Creates the signals over the host's notifiers.
  BakePauseSignals({
    required this.panelVisible,
    required this.scrolling,
    required this.panelOpening,
  }) : _any = Listenable.merge(<Listenable>[
         panelVisible,
         scrolling,
         panelOpening,
       ]);

  /// Whether the panel is on screen. A hidden panel bakes nothing.
  final ValueListenable<bool> panelVisible;

  /// Whether a scroll, drag or fling is in progress (including the ballistic
  /// phase) on the catalog being baked for.
  final ValueListenable<bool> scrolling;

  /// Whether the panel open animation is running.
  final ValueListenable<bool> panelOpening;

  final Listenable _any;

  /// Whether baking may run right now.
  bool get allowsBaking =>
      panelVisible.value && !scrolling.value && !panelOpening.value;

  /// Calls [listener] whenever any signal changes.
  void addListener(VoidCallback listener) => _any.addListener(listener);

  /// Removes a listener added with [addListener].
  void removeListener(VoidCallback listener) => _any.removeListener(listener);
}
