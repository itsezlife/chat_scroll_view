import 'dart:ui' show Offset, Rect;

import 'package:panel_presentation/src/controller/panel_presentation_controller.dart';
import 'package:panel_presentation/src/kind/panel_presentation.dart';
import 'package:panel_presentation/src/kind/panel_visibility.dart';
import 'package:panel_presentation/src/policy/panel_presentation_policy.dart';
import 'package:panel_presentation/src/time/panel_clock.dart';

/// Where on screen a toggle or an exempt region is, or null while it is not
/// laid out.
typedef PopupToggleBounds = Rect? Function();

/// The pointer rules of an anchored popup, without widgets: what hovering
/// the toggle or the popup opens, what leaving hides and what a hold defers.
///
/// ## The machine
///
/// | Event | Effect |
/// | --- | --- |
/// | mouse enters the toggle | opens at once (no delay); turns a fade-out back |
/// | mouse leaves the toggle | hide at the next event pass (a 0 ms timer) |
/// | mouse enters the popup | cancels the pending hide; turns a fade-out back |
/// | mouse leaves the popup | hide after the policy's leave delay; at the next pass if the popup is still appearing |
/// | a hold is released, pointer away | hide after the policy's after-hold delay |
/// | a timer fires under a hold | dropped; the release arms the after-hold delay |
///
/// The toggle's leave waits for the next event pass because the popup's
/// rectangle touches the toggle's: crossing from one to the other leaves the
/// first and enters the second in one pass, and the entry cancels the hide.
/// There is no other timer. In particular an interaction inside the panel
/// arms nothing: a popup the pointer never left, or that something holds,
/// stays until dismissed.
///
/// One timer slot serves every delay: arming again restarts it. Every wait
/// goes through the [PanelClock]. The policy supplies the delays and which
/// dismissals apply; this class never reads the wall clock or a pointer.
///
/// Bound to one controller on first use. Touch and stylus never hover-open,
/// and a popup last driven by touch has no leave or after-hold delay: it
/// closes by click, Escape or an outside press.
final class PopupHover {
  /// Rules waiting on [clock].
  PopupHover(this._clock);

  final PanelClock _clock;
  final _toggles = <PopupToggleBounds>{};
  final _exempt = <PopupToggleBounds>{};
  PanelPresentationController? _controller;
  PanelTimer? _timer;
  var _overToggle = false;
  var _overPopup = false;
  var _touchDriven = false;
  var _guard = false;
  var _disposed = false;

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
  }

  /// Registers where a toggle is. A press on it never dismisses (the toggle
  /// handles its own click: hiding first would let that click open the popup
  /// again), and the popup bridges the gap down to it. Returns the function
  /// that removes it.
  void Function() registerToggle(PopupToggleBounds bounds) {
    _toggles.add(bounds);
    final unexempt = registerExempt(bounds);
    return () {
      _toggles.remove(bounds);
      unexempt();
    };
  }

  /// Registers a region a press inside which does not dismiss the popup, such
  /// as the composer's input area: the user clicking back into it to keep
  /// typing is not leaving. Returns the function that removes it.
  void Function() registerExempt(PopupToggleBounds bounds) {
    _exempt.add(bounds);
    return () => _exempt.remove(bounds);
  }

  /// The registered toggles that are laid out, as global rectangles.
  Iterable<Rect> get toggleRects sync* {
    for (final bounds in _toggles) {
      if (bounds() case final rect?) yield rect;
    }
  }

  /// A mouse pointer entered a toggle.
  void toggleEntered(PanelPresentationController controller) {
    bind(controller);
    _overToggle = true;
    _touchDriven = false;
    _cancel();
    if (!controller.policy.hoverOpens) return;
    final canOpen = switch (controller.state.value) {
      PanelVisibility$Hidden() => true,
      PanelVisibility$Hiding(kind: AnchoredPopup()) => true,
      PanelVisibility$Hiding() ||
      PanelVisibility$Showing() ||
      PanelVisibility$Shown() => false,
    };
    if (!canOpen) return;
    final target = controller.policy.resolve(
      window: controller.window.value,
      dockPreferred: controller.dockPreferred.value,
    );
    if (target case AnchoredPopup()) {
      controller.show(kind: const AnchoredPopup());
    }
  }

  /// A mouse pointer left a toggle.
  void toggleExited() {
    _overToggle = false;
    _scheduleLeave(Duration.zero);
  }

  /// A toggle left the tree with the pointer over it: no exit will come, so
  /// the pointer is no longer on it, and no hide is owed for it.
  void toggleRemoved() => _overToggle = false;

  /// A mouse pointer entered the popup.
  void popupEntered() {
    _overPopup = true;
    _touchDriven = false;
    _cancel();
    final controller = _controller;
    if (controller == null || !controller.policy.hoverOpens) return;
    if (controller.state.value case PanelVisibility$Hiding(
      kind: AnchoredPopup(),
    )) {
      controller.show();
    }
  }

  /// A mouse pointer left the popup.
  void popupExited() {
    _overPopup = false;
    final controller = _controller;
    if (controller == null) return;
    // A popup that is still appearing has no grace: nothing is worth waiting
    // for in an animation the pointer has already walked away from.
    final animating = controller.state.value.isMoving;
    _scheduleLeave(animating ? Duration.zero : controller.policy.leaveDelay);
  }

  /// A touch or stylus pressed the popup or a toggle: the popup is now
  /// driven by touch and keeps open until dismissed.
  void touched() {
    _touchDriven = true;
    _cancel();
  }

  /// A press landed outside the popup at [globalPosition]. Dismisses unless
  /// it hit a toggle or another exempt region.
  void pressedOutside(Offset globalPosition) {
    final controller = _controller;
    if (controller == null || !_isOpen) return;
    for (final bounds in _exempt) {
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
    }
    _controller = null;
    _toggles.clear();
    _exempt.clear();
  }

  bool get _isOpen => switch (_controller?.state.value) {
    PanelVisibility$Showing(kind: AnchoredPopup()) ||
    PanelVisibility$Shown(kind: AnchoredPopup()) => true,
    _ => false,
  };

  bool _allows(PanelDismissal dismissal) {
    final controller = _controller;
    return controller != null &&
        controller.policy
            .dismissalsFor(const AnchoredPopup())
            .contains(dismissal);
  }

  bool get _pointerAway => !_overPopup && !_overToggle && !_touchDriven;

  void _onState() {
    if (_controller?.state.value case PanelVisibility$Hidden()) {
      // The popup is gone from the tree, so no exit will come for it, and a
      // touch session ends with it. The toggle stays: its own exit reports.
      _cancel();
      _overPopup = false;
      _touchDriven = false;
    }
  }

  void _onGuard() {
    final controller = _controller;
    if (controller == null) return;
    final was = _guard;
    _guard = controller.autoHideGuard.value;
    if (was && !_guard) _armAfterHold();
  }

  void _scheduleLeave(Duration delay) {
    final controller = _controller;
    if (controller == null || !_isOpen || !_pointerAway) return;
    if (!_allows(PanelDismissal.leave) || controller.autoHideGuard.value) {
      return;
    }
    _arm(delay);
  }

  // The leave that a hold swallowed is owed once it is released.
  void _armAfterHold() {
    final controller = _controller;
    if (controller == null || !_isOpen || !_pointerAway) return;
    if (!_allows(PanelDismissal.afterHold)) return;
    _arm(controller.policy.afterHoldDelay);
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
    if (_isOpen && _pointerAway) controller.hide();
  }
}
