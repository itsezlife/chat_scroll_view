import 'package:flutter/foundation.dart';

/// Aggregates host chrome into the reserved insets a chat viewport consumes.
///
/// The viewport does not own composer, keyboard, or selection chrome. It
/// only reads `topPadding` / `bottomPadding` listenables. This object is
/// the single place those listenables are computed:
///
/// ```text
/// topPadding    = safeTop + headerReserve
/// bottomPadding = composerHeight + keyboard
/// ```
///
/// **Reserved vs overlay.** Only chrome that occludes messages writes a
/// reserve ([headerReserve], [setComposerHeight]). Overlay widgets (unread
/// pill, jump buttons) **read** [bottomPadding] to sit above that edge and
/// must not add to it.
///
/// **Keyboard** is a live geometric signal, not a second scroll writer. The
/// composer lifts by [keyboard]; the viewport's [bottomPadding] already
/// includes that same value so messages clear both composer and IME.
///
/// **Measurement** of composer height is a bootstrap and later correction,
/// not a second coordinate system. Composer height defaults to 96 until
/// the first layout report — that default is idle occupancy, not a theme
/// token.
///
/// Call [dispose] when the host leaves the tree. Do not dispose
/// [headerReserve] separately; this object owns every notifier it exposes.
final class ChatViewportInsets {
  /// Creates an aggregator.
  ///
  /// [composerHeight] seeds [bottomPadding] until the first measure.
  ChatViewportInsets({
    double composerHeight = 96,
    double safeTop = 0,
    double headerReserve = 0,
    double keyboard = 0,
  }) : _composerHeight = composerHeight,
       _safeTop = safeTop,
       headerReserve = ValueNotifier<double>(headerReserve),
       _keyboard = ValueNotifier<double>(keyboard),
       _topPadding = ValueNotifier<double>(safeTop + headerReserve),
       _bottomPadding = ValueNotifier<double>(composerHeight + keyboard) {
    this.headerReserve.addListener(_publish);
  }

  double _safeTop;
  double _composerHeight;

  /// Tick-driven header occupancy written by selection chrome.
  ///
  /// Selection UI assigns `progress × barHeight` on each animation tick.
  /// Safe-area top is **not** included; feed that through [setSafeTop].
  final ValueNotifier<double> headerReserve;

  final ValueNotifier<double> _keyboard;
  final ValueNotifier<double> _topPadding;
  final ValueNotifier<double> _bottomPadding;

  /// Keyboard height used to lift the composer widget.
  ///
  /// Equal to the keyboard term in [bottomPadding]. Overlay chrome should
  /// still key off [bottomPadding], not this listenable.
  ValueListenable<double> get keyboard => _keyboard;

  /// Reserved top inset for the viewport `topPadding`.
  ///
  /// `safeTop + headerReserve`.
  ValueListenable<double> get topPadding => _topPadding;

  /// Reserved bottom inset for the viewport `bottomPadding`.
  ///
  /// `composerHeight + keyboard`. Overlay chrome positions against this
  /// value and does not contribute to it.
  ValueListenable<double> get bottomPadding => _bottomPadding;

  /// Persistent top safe-area inset (status bar / notch).
  ///
  /// Hosts should push `MediaQuery.viewPadding.top` from
  /// `didChangeDependencies` so rotation and inset changes republish.
  void setSafeTop(double value) {
    if (_safeTop == value) return;
    _safeTop = value;
    _publish();
  }

  /// Measured composer occupancy, including its own bottom safe-area pad.
  ///
  /// Does **not** include keyboard height; keyboard is applied outside the
  /// measure and added here via [setKeyboard].
  void setComposerHeight(double value) {
    if (_composerHeight == value) return;
    _composerHeight = value;
    _publish();
  }

  /// Live keyboard height in logical pixels.
  void setKeyboard(double value) {
    if (_keyboard.value == value) return;
    _keyboard.value = value;
    _publish();
  }

  /// Releases every notifier this object owns.
  void dispose() {
    headerReserve.removeListener(_publish);
    headerReserve.dispose();
    _keyboard.dispose();
    _topPadding.dispose();
    _bottomPadding.dispose();
  }

  void _publish() {
    _topPadding.value = _safeTop + headerReserve.value;
    _bottomPadding.value = _composerHeight + _keyboard.value;
  }
}
