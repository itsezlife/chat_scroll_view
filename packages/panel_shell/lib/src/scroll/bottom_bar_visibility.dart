import 'package:content_model/content_model.dart';
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
  /// A visibility starting shown, toggling at [toggleOffset] pixels.
  BottomBarVisibility({this.toggleOffset = defaultToggleOffset});

  /// Pixels of one-direction scroll that toggle the bar.
  static const double defaultToggleOffset = 38;

  /// Pixels of one-direction scroll that toggle this bar.
  final double toggleOffset;

  final _visible = ObservableValue<bool>(true);
  var _accumulated = 0.0;
  var _pinnedHidden = false;

  /// Whether the bar is shown. Held down while [pinnedHidden].
  ValueObservable<bool> get visible => _visible;

  /// Whether something else (an open search) keeps the bar hidden.
  ///
  /// Scroll activity is still tracked underneath, but cannot show the bar until
  /// the pin is released, which shows it.
  bool get pinnedHidden => _pinnedHidden;

  set pinnedHidden(bool value) {
    if (_pinnedHidden == value) return;
    _pinnedHidden = value;
    _accumulated = 0;
    _visible.value = !value;
  }

  /// Takes one report of the active page's scroll into account.
  void apply(PageScrollActivity activity) {
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

  /// Stops notifying and drops listeners.
  void dispose() => _visible.dispose();

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
    _accumulated = 0;
    _visible.value = shown && !_pinnedHidden;
  }
}
