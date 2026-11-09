import 'package:flutter/foundation.dart';

/// The facts that decide whether background baking may run, as small signals
/// the host owns and updates: baking never competes with something the user
/// is looking at or touching, and never runs for glyphs nobody is shown.
///
/// Baking runs only while the panel is visible, a surface that draws the
/// glyphs is shown in it, nothing is scrolling and the panel is not animating
/// open. Wiring each signal to the real viewport and panel is the host's job;
/// this type only reads them.
final class BakePauseSignals {
  /// Creates the signals over the host's notifiers. Without [glyphsShown] the
  /// visible panel is taken to show the glyphs.
  BakePauseSignals({
    required this.panelVisible,
    required this.scrolling,
    required this.panelOpening,
    this.glyphsShown,
  }) : _any = Listenable.merge(<Listenable>[
         panelVisible,
         scrolling,
         panelOpening,
         ?glyphsShown,
       ]);

  /// Whether the panel is on screen. A hidden panel bakes nothing.
  final ValueListenable<bool> panelVisible;

  /// Whether a scroll, drag or fling is in progress (including the ballistic
  /// phase) on any surface the bake must not compete with: the catalog being
  /// baked for, and whatever else the host says moves.
  final ValueListenable<bool> scrolling;

  /// Whether the panel open animation is running.
  final ValueListenable<bool> panelOpening;

  /// Whether a surface that draws these glyphs is shown (the catalogue page
  /// that lists them is the selected one), or null when the visible panel
  /// always shows them. A panel showing another page bakes nothing: the bake
  /// would cost that page's frames for glyphs nobody sees.
  final ValueListenable<bool>? glyphsShown;

  final Listenable _any;

  /// Whether baking may run right now.
  bool get allowsBaking =>
      panelVisible.value &&
      (glyphsShown?.value ?? true) &&
      !scrolling.value &&
      !panelOpening.value;

  /// Calls [listener] whenever any signal changes.
  void addListener(VoidCallback listener) => _any.addListener(listener);

  /// Removes a listener added with [addListener].
  void removeListener(VoidCallback listener) => _any.removeListener(listener);
}
