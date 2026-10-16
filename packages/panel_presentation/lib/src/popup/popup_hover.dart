import 'dart:ui' show Offset, Rect;

import 'package:panel_presentation/src/controller/panel_presentation_controller.dart';
import 'package:panel_presentation/src/kind/panel_presentation.dart';
import 'package:panel_presentation/src/kind/panel_visibility.dart';
import 'package:panel_presentation/src/policy/panel_presentation_policy.dart';
import 'package:panel_presentation/src/time/panel_clock.dart';

/// Where on screen a toggle is, or null while it is not laid out.
typedef PopupToggleBounds = Rect? Function();

/// The pointer rules of an anchored popup, without widgets: what hovering
/// the toggle or the popup opens, what leaving hides and what an interaction
/// delays.
///
/// One timer slot serves both delays, as a single hide timer does in the
/// reference client: arming it again restarts it. Every delay waits on the
/// [PanelClock], and a timer that fires while the controller's auto-hide
/// guard is up does nothing. The policy supplies the delays and which
/// dismissals apply; this class never reads the wall clock or a pointer.
///
/// Bound to one controller on first use. Touch and stylus never hover-open,
/// and a popup last driven by touch has no leave or idle delay: it closes by
/// click, Escape or an outside press.
final class PopupHover {
  /// Rules waiting on [clock].
  PopupHover(this._clock);

  final PanelClock _clock;
  final _toggles = <PopupToggleBounds>{};
  PanelPresentationController? _controller;
  PanelTimer? _timer;
  var _overToggle = false;
  var _overPopup = false;
  var _touchDriven = false;
  var _openedByHover = false;
  var _guard = false;
  var _disposed = false;

  /// Whether the popup now showing was opened by a hover, so it must not
  /// take focus from the composer the user is typing in.
  bool get openedByHover => _openedByHover;

  /// Binds to [controller] on first call; later calls must name the same one.
  void bind(PanelPresentationController controller) {
    if (_disposed) return;
    if (_controller != null) {
      assert(
        identical(_controller, controller),
        'An anchored popup strategy serves one controller.',
      );
      return;
    }
    _controller = controller;
    _guard = controller.autoHideGuard.value;
    controller.state.addListener(_onState);
    controller.autoHideGuard.addListener(_onGuard);
    controller.interactions.addListener(_onInteraction);
  }

  /// Registers where a toggle is, for outside-press tests. Returns the
  /// function that removes it.
  void Function() registerToggle(PopupToggleBounds bounds) {
    _toggles.add(bounds);
    return () => _toggles.remove(bounds);
  }

  /// A mouse pointer entered a toggle.
  void toggleEntered(PanelPresentationController controller) {
    bind(controller);
    _overToggle = true;
    _touchDriven = false;
    _cancel();
    if (!controller.policy.hoverOpens) return;
    final state = controller.state.value;
    final canOpen =
        state is PanelVisibility$Hidden ||
        (state is PanelVisibility$Hiding && state.kind is AnchoredPopup);
    if (!canOpen) return;
    final target = controller.policy.resolve(
      windowClass: controller.window.value.windowClass,
      dockPreferred: controller.dockPreferred.value,
    );
    if (target is! AnchoredPopup) return;
    if (state is PanelVisibility$Hidden) _openedByHover = true;
    controller.show(kind: const AnchoredPopup());
  }

  /// A mouse pointer left a toggle.
  void toggleExited() {
    _overToggle = false;
    _scheduleLeave();
  }

  /// A mouse pointer entered the popup.
  void popupEntered() {
    _overPopup = true;
    _touchDriven = false;
    _cancel();
  }

  /// A mouse pointer left the popup.
  void popupExited() {
    _overPopup = false;
    _scheduleLeave();
  }

  /// A touch or stylus pressed the popup or a toggle: the popup is now
  /// driven by touch and keeps open until dismissed.
  void touched() {
    _touchDriven = true;
    _cancel();
  }

  /// A press landed outside the popup at [globalPosition]. Dismisses unless
  /// it hit a toggle, which handles itself: hiding first would let the
  /// toggle's own click open it again.
  void pressedOutside(Offset globalPosition) {
    final controller = _controller;
    if (controller == null || !_isOpen) return;
    for (final bounds in _toggles) {
      if (bounds()?.contains(globalPosition) ?? false) return;
    }
    if (_allows(PanelDismissal.outsidePress)) controller.hide();
  }

  /// Stops the timer and drops every listener. Idempotent.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _cancel();
    final controller = _controller;
    if (controller != null && !controller.isDisposed) {
      controller.state.removeListener(_onState);
      controller.autoHideGuard.removeListener(_onGuard);
      controller.interactions.removeListener(_onInteraction);
    }
    _controller = null;
    _toggles.clear();
  }

  bool get _isOpen {
    final state = _controller?.state.value;
    return (state is PanelVisibility$Showing ||
            state is PanelVisibility$Shown) &&
        state?.kind is AnchoredPopup;
  }

  bool _allows(PanelDismissal dismissal) {
    final controller = _controller;
    return controller != null &&
        controller.policy
            .dismissalsFor(const AnchoredPopup())
            .contains(dismissal);
  }

  bool get _pointerAway => !_overPopup && !_overToggle && !_touchDriven;

  void _onState() {
    if (_controller?.state.value is PanelVisibility$Hidden) {
      _cancel();
      _overPopup = false;
      _openedByHover = false;
    }
  }

  void _onGuard() {
    final controller = _controller;
    if (controller == null) return;
    final was = _guard;
    _guard = controller.autoHideGuard.value;
    if (was && !_guard) _armIdle();
  }

  void _onInteraction() => _armIdle();

  void _scheduleLeave() {
    final controller = _controller;
    if (controller == null || !_isOpen || !_pointerAway) return;
    if (!_allows(PanelDismissal.leave) || controller.autoHideGuard.value) {
      return;
    }
    _arm(controller.policy.leaveDelay);
  }

  void _armIdle() {
    final controller = _controller;
    if (controller == null || !_isOpen || !_pointerAway) return;
    if (!_allows(PanelDismissal.idle)) return;
    _arm(controller.policy.idleDelay);
  }

  void _arm(Duration delay) {
    _cancel();
    _timer = _clock.after(delay, _fire);
  }

  void _cancel() {
    _timer?.cancel();
    _timer = null;
  }

  void _fire() {
    _timer = null;
    final controller = _controller;
    if (controller == null || controller.isDisposed) return;
    if (controller.autoHideGuard.value) return;
    if (_isOpen) controller.hide();
  }
}
