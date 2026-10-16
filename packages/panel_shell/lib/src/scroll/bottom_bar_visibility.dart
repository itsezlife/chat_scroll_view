import 'package:listen/listen.dart';
import 'package:panel_shell/src/scroll/page_scroll_activity.dart';

/// Decides from [PageScrollActivity] alone whether the bottom bar is shown.
///
/// The rule is the one the bar has always had, minus its clock: reading on
/// (the content moving toward its end) for [toggleOffset] pixels hides the
/// bar, moving back for as far shows it, and a net movement the way the bar
/// already points is forgotten. A programmatic scroll and a rest at either end show it
/// at once. Where the old code suppressed deltas that arrived within a
/// timeout after a tap, a page now reports a [PageScrollJump] and the
/// ambiguity does not arise.
///
/// A mutable accumulator by role (it holds a count between calls), unlike the
/// immutable activities it consumes.
final class BottomBarVisibility {
  /// A visibility starting shown, toggling at [toggleOffset] pixels while
  /// [hidesOnScroll].
  BottomBarVisibility({
    this.toggleOffset = defaultToggleOffset,
    bool hidesOnScroll = true,
  }) : _hidesOnScroll = hidesOnScroll;

  /// Pixels of one-direction scroll that toggle the bar.
  static const double defaultToggleOffset = 38;

  /// Pixels of one-direction scroll that toggle this bar.
  final double toggleOffset;

  final _visible = ValueNotifier<bool>(true);
  var _accumulated = 0.0;
  var _pinnedHidden = false;
  bool _hidesOnScroll;
  var _disposed = false;

  /// Whether the bar is shown. Held down while [pinnedHidden].
  ValueListenable<bool> get visible => _visible;

  /// Whether reading on hides the bar. False for a bar that only an open
  /// search takes away (the pointer arrangement): scroll activity then changes
  /// nothing.
  bool get hidesOnScroll => _hidesOnScroll;

  set hidesOnScroll(bool value) {
    if (_disposed || _hidesOnScroll == value) return;
    _hidesOnScroll = value;
    show();
  }

  /// Whether something else (an open search) keeps the bar hidden.
  ///
  /// Scroll activity is still tracked underneath, but cannot show the bar until
  /// the pin is released, which shows it.
  bool get pinnedHidden => _pinnedHidden;

  set pinnedHidden(bool value) {
    if (_disposed || _pinnedHidden == value) return;
    _pinnedHidden = value;
    _accumulated = 0;
    _visible.value = !value;
  }

  /// Takes one report of the active page's scroll into account.
  void apply(PageScrollActivity activity) {
    if (!_hidesOnScroll) return;
    switch (activity) {
      case PageScrollDrag(:final delta):
      case PageScrollFling(:final delta):
        _accumulate(delta);
      case PageScrollJump():
        show();
      case PageScrollIdle(:final atEdge):
        if (atEdge) show();
    }
  }

  /// Shows the bar and forgets the distance counted so far.
  void show() => _set(true);

  /// Stops notifying and drops listeners. Idempotent; later input changes
  /// nothing.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _visible.dispose();
  }

  void _accumulate(double delta) {
    _accumulated += delta;
    if (_accumulated >= toggleOffset) {
      _set(false);
    } else if (_accumulated <= -toggleOffset) {
      _set(true);
    } else if ((_visible.value && _accumulated < 0) ||
        (!_visible.value && _accumulated > 0)) {
      // Moving the way the bar already points: the count of the opposite
      // direction is stale.
      _accumulated = 0;
    }
  }

  void _set(bool shown) {
    if (_disposed) return;
    _accumulated = 0;
    _visible.value = shown && !_pinnedHidden;
  }
}
