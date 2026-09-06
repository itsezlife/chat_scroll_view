import 'package:chat_scroll_view_example/src/features/chat/utils/ios_keyboard_safe_peel.dart';
import 'package:flutter/foundation.dart';

/// Aggregates host chrome into the reserved insets a chat viewport consumes.
///
/// On iOS, [composerHeight] from measure includes the idle home-indicator
/// band. While [keyboard] occupancy rises, that band is peeled out of the
/// reserve via [iosKeyboardSafeBandPeel] so [bottomPadding] stays aligned
/// with the physical keyboard slot (same lerp as the host slot layout).
final class ChatViewportInsets {
  /// Creates an aggregator.
  ChatViewportInsets({
    double composerHeight = 96,
    double safeTop = 0,
    double headerReserve = 0,
    double searchReserve = 0,
    double keyboard = 0,
  }) : _composerHeight = composerHeight,
       _safeTop = safeTop,
       _safeBottom = 0,
       _keyboardTarget = 0,
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
  double _safeBottom;
  double _keyboardTarget;
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

  /// Live keyboard / keyboard-panel extent in logical pixels.
  void setKeyboard(double value) {
    if (_keyboard.value == value) return;
    _keyboard.value = value;
    _publish();
  }

  /// Bottom safe band (`MediaQuery.viewPadding.bottom`) for iOS peel math.
  void setSafeBottom(double value) {
    if (_safeBottom == value) return;
    _safeBottom = value;
    _publish();
  }

  /// Open keyboard / panel target for iOS safe-band peel (`keyboard / target`).
  void setKeyboardTarget(double value) {
    if (_keyboardTarget == value) return;
    _keyboardTarget = value;
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
    final keyboard = _keyboard.value;
    _chromeTop.value = chrome;
    _topPadding.value = chrome + _searchReserve;

    var composer = _composerHeight;
    if (_safeBottom > 0) {
      final peeled = iosKeyboardSafeBandPeel(
        safeBottom: _safeBottom,
        keyboard: keyboard,
        keyboardTarget: _keyboardTarget,
      );
      composer = _composerHeight - (_safeBottom - peeled);
    }
    _bottomPadding.value = composer + keyboard;
  }
}
