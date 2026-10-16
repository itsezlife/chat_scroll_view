import 'package:flutter/foundation.dart';
import 'package:listen/listen.dart' as listen;
import 'package:panel_presentation/panel_presentation.dart';

/// Aggregates host chrome into the reserved insets a chat viewport consumes
/// (`docs/architecture/14-host-chrome-insets.md`).
///
/// ```text
/// bottomPadding = composer extent + presentation occupancy.bottom
/// inlineEnd     = presentation occupancy.inlineEnd   // applied in layout
/// topPadding    = safe top + header reserve + search reserve
/// ```
///
/// The composer extent already holds its own bottom safe-area pad, and the
/// occupancy of a keyboard presentation already holds the live soft keyboard,
/// so neither is added a second time. Overlay chrome that only reads the
/// reserved edge (the page-down button) takes [bottomPadding] and adds
/// nothing to it.
///
/// It follows the two observables it is given and disposes neither: their
/// owners do.
final class ChatViewportInsets {
  /// Aggregates [composerExtent] and [occupancy] into the reserved insets.
  ChatViewportInsets({
    required listen.ValueListenable<double> composerExtent,
    required listen.ValueListenable<PanelOccupancy> occupancy,
    double safeTop = 0,
  }) : _composerExtent = composerExtent,
       _occupancy = occupancy,
       _safeTop = safeTop,
       headerReserve = ValueNotifier<double>(0),
       _chromeTop = ValueNotifier<double>(safeTop),
       _topPadding = ValueNotifier<double>(safeTop),
       _bottomPadding = ValueNotifier<double>(0),
       _inlineEnd = ValueNotifier<double>(0) {
    _publishBottom();
    headerReserve.addListener(_publishTop);
    composerExtent.addListener(_publishBottom);
    occupancy.addListener(_publishBottom);
  }

  /// What the viewport reserves for the composer until the composer has
  /// published its first extent, so the first frame is not zero.
  static const double composerSeed = 96;

  final listen.ValueListenable<double> _composerExtent;
  final listen.ValueListenable<PanelOccupancy> _occupancy;
  double _safeTop;
  double _searchReserve = 0;
  var _disposed = false;

  /// Tick-driven header occupancy written by selection chrome.
  ///
  /// Selection UI assigns `progress × barHeight` on each animation tick.
  /// Safe-area top is **not** included; feed that through [setSafeTop].
  final ValueNotifier<double> headerReserve;

  final ValueNotifier<double> _chromeTop;
  final ValueNotifier<double> _topPadding;
  final ValueNotifier<double> _bottomPadding;
  final ValueNotifier<double> _inlineEnd;

  /// Top edge for overlay chrome that sits below the safe area / selection
  /// bar but is not itself part of the viewport reserve.
  ///
  /// `safeTop + headerReserve`. Search field and demo toolbar position
  /// against this so the search reserve does not displace them.
  ValueListenable<double> get chromeTop => _chromeTop;

  /// Reserved top inset for the viewport `topPadding`.
  ///
  /// `safeTop + headerReserve + searchReserve`.
  ValueListenable<double> get topPadding => _topPadding;

  /// Reserved bottom inset for the viewport `bottomPadding`.
  ///
  /// The composer extent (the [composerSeed] before it is known) plus the
  /// presentation's bottom occupancy. Overlay chrome positions against this
  /// value and does not contribute to it.
  ValueListenable<double> get bottomPadding => _bottomPadding;

  /// The width a docked presentation takes at the end edge; zero otherwise.
  ///
  /// Not padding: the host shrinks the whole chat region by it in layout,
  /// mirrored in right-to-left text.
  ValueListenable<double> get inlineEnd => _inlineEnd;

  /// Persistent top safe-area inset (status bar / notch).
  ///
  /// Hosts push `MediaQuery.viewPadding.top` from `didChangeDependencies` so
  /// rotation and inset changes republish.
  void setSafeTop(double value) {
    if (_safeTop == value) return;
    _safeTop = value;
    _publishTop();
  }

  /// Measured open-search occupancy, including its outer pad above the field.
  ///
  /// Zero while search chrome is closed. Does **not** include the safe top or
  /// [headerReserve]; those are added in [topPadding] / [chromeTop].
  void setSearchReserve(double value) {
    if (_searchReserve == value) return;
    _searchReserve = value;
    _publishTop();
  }

  /// Stops following the composer and the presentation and releases every
  /// notifier this object owns; the two observables it was given stay theirs.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    headerReserve.removeListener(_publishTop);
    _composerExtent.removeListener(_publishBottom);
    _occupancy.removeListener(_publishBottom);
    headerReserve.dispose();
    _chromeTop.dispose();
    _topPadding.dispose();
    _bottomPadding.dispose();
    _inlineEnd.dispose();
  }

  void _publishTop() {
    final chrome = _safeTop + headerReserve.value;
    _chromeTop.value = chrome;
    _topPadding.value = chrome + _searchReserve;
  }

  void _publishBottom() {
    final extent = _composerExtent.value;
    final occupancy = _occupancy.value;
    _bottomPadding.value =
        (extent > 0 ? extent : composerSeed) + occupancy.bottom;
    _inlineEnd.value = occupancy.inlineEnd;
  }
}
