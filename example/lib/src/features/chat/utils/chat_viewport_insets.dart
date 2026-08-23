import 'package:flutter/foundation.dart';

/// Aggregates host chrome into the reserved insets a chat viewport consumes.
///
/// The viewport does not own composer, keyboard, or selection chrome. It
/// only reads `topPadding` / `bottomPadding` listenables. This object is
/// the single place those listenables are computed:
///
/// ```text
/// chromeTop     = safeTop + headerReserve
/// topPadding    = chromeTop + searchReserve
/// bottomPadding = composerHeight + keyboard
/// ```
///
/// **Reserved vs overlay.** Only chrome that occludes messages writes a
/// reserve ([headerReserve], [setSearchReserve], [setComposerHeight]).
/// Overlay widgets (unread pill, jump buttons, search field, demo toolbar)
/// **read** [chromeTop] / [bottomPadding] to sit against that edge and must
/// not add themselves into the value they read.
///
/// **Search** writes [setSearchReserve] with the measured open search field
/// height (including its outer pad). Position the field against [chromeTop]
/// so growing [topPadding] does not push the field further down.
///
/// **Keyboard** is a live geometric signal, not a second scroll writer. The
/// composer lifts by [keyboard]; the viewport's [bottomPadding] already
/// includes that same value so messages clear both composer and IME.
///
/// **Measurement** of composer height is a bootstrap and later correction,
/// not a second coordinate system. Composer height defaults to 96 until
/// the first layout report — that default is idle occupancy, not a theme
/// token. The measured value must include the composer's own bottom
/// safe-area pad and island→keyboard gap; it must **not** include keyboard.
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
    double searchReserve = 0,
    double keyboard = 0,
  }) : _composerHeight = composerHeight,
       _safeTop = safeTop,
       _searchReserve = searchReserve,
       headerReserve = ValueNotifier<double>(headerReserve),
       _keyboard = ValueNotifier<double>(keyboard),
       _chromeTop = ValueNotifier<double>(safeTop + headerReserve),
       _topPadding = ValueNotifier<double>(
         safeTop + headerReserve + searchReserve,
       ),
       _bottomPadding = ValueNotifier<double>(composerHeight + keyboard) {
    this.headerReserve.addListener(_publish);
  }

  double _safeTop;
  double _composerHeight;
  double _searchReserve;

  /// Tick-driven header occupancy written by selection chrome.
  ///
  /// Selection UI assigns `progress × barHeight` on each animation tick.
  /// Safe-area top is **not** included; feed that through [setSafeTop].
  final ValueNotifier<double> headerReserve;

  final ValueNotifier<double> _keyboard;
  final ValueNotifier<double> _chromeTop;
  final ValueNotifier<double> _topPadding;
  final ValueNotifier<double> _bottomPadding;

  /// Keyboard height used to lift the composer widget.
  ///
  /// Equal to the keyboard term in [bottomPadding]. Overlay chrome should
  /// still key off [bottomPadding], not this listenable.
  ValueListenable<double> get keyboard => _keyboard;

  /// Top edge for overlay chrome that sits below the safe area / selection
  /// bar but is not itself part of the viewport reserve.
  ///
  /// `safeTop + headerReserve`. Search field and demo toolbar position
  /// against this so [searchReserve] does not displace them.
  ValueListenable<double> get chromeTop => _chromeTop;

  /// Reserved top inset for the viewport `topPadding`.
  ///
  /// `safeTop + headerReserve + searchReserve`.
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

  /// Measured open-search occupancy, including its outer pad above the field.
  ///
  /// Zero while search chrome is closed. Does **not** include [safeTop] or
  /// [headerReserve]; those are added in [topPadding] / [chromeTop].
  void setSearchReserve(double value) {
    if (_searchReserve == value) return;
    _searchReserve = value;
    _publish();
  }

  /// Measured composer occupancy, including its own bottom safe-area pad
  /// and island→keyboard gap.
  ///
  /// Does **not** include keyboard height; keyboard is applied outside the
  /// measure and added here via [setKeyboard].
  void setComposerHeight(double value) {
    if (_composerHeight == value) return;
    _composerHeight = value;
    _publish();
  }

  /// Live keyboard / emoji-panel slot height in logical pixels.
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
    _chromeTop.dispose();
    _topPadding.dispose();
    _bottomPadding.dispose();
  }

  void _publish() {
    final chrome = _safeTop + headerReserve.value;
    _chromeTop.value = chrome;
    _topPadding.value = chrome + _searchReserve;
    _bottomPadding.value = _composerHeight + _keyboard.value;
  }
}
