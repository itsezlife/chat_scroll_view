import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';
import 'package:panel_presentation/src/controller/panel_presentation_controller.dart';
import 'package:panel_presentation/src/kind/panel_occupancy.dart';
import 'package:panel_presentation/src/kind/panel_presentation.dart';
import 'package:panel_presentation/src/kind/panel_visibility.dart';
import 'package:panel_presentation/src/policy/panel_window.dart';
import 'package:panel_presentation/src/popup/anchored_popup_input.dart';
import 'package:panel_presentation/src/popup/anchored_popup_layout.dart';
import 'package:panel_presentation/src/popup/anchored_popup_style.dart';
import 'package:panel_presentation/src/popup/popup_hover.dart';
import 'package:panel_presentation/src/strategy/panel_presentation_strategy.dart';
import 'package:panel_presentation/src/time/panel_clock.dart';
import 'package:panel_shell/panel_shell.dart';

/// The **anchored popup** of desktop and web: the panel floats above the
/// composer, opens when a mouse hovers its toggle, and hides itself.
///
/// Draws [AnchoredPopup]. It mounts the controller's `PanelShell` in a
/// popup whose bottom edge sits on the top of the composer rectangle the host
/// reports with `PanelPresentationController.anchor` and whose end edge
/// sits on that rectangle's end edge (mirrored in a right-to-left layout). The
/// popup is as tall as the policy says for the reported window, grows from
/// its bottom-end corner with the `popupShow` role and shrinks back with
/// `popupHide`, and takes no space: its occupancy is always zero.
///
/// ## Pointer
///
/// The host wraps its toggle in an [AnchoredPopupToggleRegion]. A mouse
/// entering it opens the popup (a click is the host's own
/// `PanelPresentationController.toggle`); the mouse leaving the toggle or the
/// popup hides it after the policy's leave delay, entering either cancels
/// that, and an interaction in the panel with the pointer away hides it after
/// the idle delay. A held auto-hide guard (search focus, an open variant
/// picker, a page being dragged) defeats every delay. Touch and stylus never
/// open or time out the popup.
///
/// ## Dismissal and focus
///
/// A press outside the popup, other than on the toggle, hides it. Escape
/// steps back: the shell closes search first, then the popup. Focus enters
/// the popup when it opens, except when a hover opened it (the user is still
/// typing in the composer), and returns to [composerFocus] when it closes.
///
/// Every wait goes through the [PanelClock]; nothing reads the wall clock.
final class AnchoredPopupStrategy implements PanelPresentationStrategy {
  /// A strategy drawing popups in [style].
  ///
  /// [clock] defaults to the system clock. [composerFocus] is where focus goes
  /// back to when the popup closes while it held focus; null leaves focus
  /// where the framework puts it.
  AnchoredPopupStrategy({
    required this.style,
    PanelClock clock = PanelClock.system,
    this.composerFocus,
  }) : _hover = PopupHover(clock);

  /// How the popup looks.
  final AnchoredPopupStyle style;

  /// The composer's focus node, or null.
  final FocusNode? composerFocus;

  final PopupHover _hover;
  final _occupancy = ObservableValue<PanelOccupancy>(PanelOccupancy.zero);

  /// The pointer rules, shared with the toggle region.
  @internal
  PopupHover get hover => _hover;

  @override
  PanelPresentation get kind => const AnchoredPopup();

  @override
  ValueObservable<PanelOccupancy> get occupancy => _occupancy;

  @override
  Widget build(BuildContext context, PanelStrategyContext view) =>
      _PopupBody(strategy: this, view: view);

  /// Stops the delays and releases the occupancy observable. The controller
  /// and the shell are left to their owners.
  void dispose() {
    _hover.dispose();
    _occupancy.dispose();
  }
}

/// Wraps the host's toggle so a mouse hovering it opens an anchored popup.
///
/// Only [PointerDeviceKind.mouse] counts: touch and stylus press it as a
/// click, which stays the host's own handler. A press by touch or stylus
/// marks the popup touch-driven, so it has no leave or idle delay until a
/// mouse hovers again.
class AnchoredPopupToggleRegion extends StatefulWidget {
  /// A region around [child] that opens [strategy]'s popup on [controller].
  const AnchoredPopupToggleRegion({
    required this.strategy,
    required this.controller,
    required this.child,
    super.key,
  });

  /// The strategy that owns the pointer rules.
  final AnchoredPopupStrategy strategy;

  /// The controller the popup belongs to.
  final PanelPresentationController controller;

  /// The toggle.
  final Widget child;

  @override
  State<AnchoredPopupToggleRegion> createState() =>
      _AnchoredPopupToggleRegionState();
}

class _AnchoredPopupToggleRegionState extends State<AnchoredPopupToggleRegion> {
  late void Function() _unregister;

  @override
  void initState() {
    super.initState();
    widget.strategy.hover.bind(widget.controller);
    _unregister = widget.strategy.hover.registerToggle(_bounds);
  }

  @override
  void dispose() {
    _unregister();
    super.dispose();
  }

  Rect? _bounds() {
    if (context.findRenderObject() case final RenderBox box
        when box.attached && box.hasSize) {
      return box.localToGlobal(Offset.zero) & box.size;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (event) {
      if (event.kind == PointerDeviceKind.mouse) {
        widget.strategy.hover.toggleEntered(widget.controller);
      }
    },
    onExit: (event) {
      if (event.kind == PointerDeviceKind.mouse) {
        widget.strategy.hover.toggleExited();
      }
    },
    child: Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        if (event.kind != PointerDeviceKind.mouse) {
          widget.strategy.hover.touched();
        }
      },
      child: widget.child,
    ),
  );
}

class _PopupBody extends StatefulWidget {
  const _PopupBody({required this.strategy, required this.view});

  final AnchoredPopupStrategy strategy;
  final PanelStrategyContext view;

  @override
  State<_PopupBody> createState() => _PopupBodyState();
}

class _PopupBodyState extends State<_PopupBody>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(vsync: this);
  final _scope = FocusScopeNode(debugLabel: 'AnchoredPopup');
  PanelAutoHideHold? _dragHold;
  Curve _curve = Curves.linear;
  var _synced = false;
  var _disposed = false;

  PanelPresentationController get _controller => widget.view.controller;
  PopupHover get _hover => widget.strategy.hover;

  @override
  void initState() {
    super.initState();
    _hover.bind(_controller);
    // autofocus would be ignored while the composer holds focus, so ask once
    // the scope is in the tree.
    if (!_hover.openedByHover) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_disposed && !widget.view.visibility.isHiding) {
          _scope.requestFocus();
        }
      });
    }
    _motion.value = widget.view.visibility.isShowing ? 0 : 1;
    _controller.shell.scrollActivity.addListener(_onScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_synced) {
      _synced = true;
      _play();
    }
  }

  @override
  void didUpdateWidget(_PopupBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.view.visibility != widget.view.visibility) {
      if (widget.view.visibility.isHiding) _restoreFocus();
      _play();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _controller.shell.scrollActivity.removeListener(_onScroll);
    _dragHold?.release();
    _dragHold = null;
    _restoreFocus();
    _motion.dispose();
    _scope.dispose();
    super.dispose();
  }

  void _onScroll(PageScrollActivity activity) {
    switch (activity) {
      case PageScrollDrag() || PageScrollFling():
        _dragHold ??= _controller.holdAutoHide();
      case PageScrollJump() || PageScrollIdle():
        _dragHold?.release();
        _dragHold = null;
    }
  }

  // Plays the motion for the visibility being shown, and reports its end.
  // A motion cancelled by a newer one reports too; the controller ignores a
  // report for a state that has been replaced.
  void _play() {
    final view = widget.view;
    final visibility = view.visibility;
    final policy = _controller.policy;
    final motion = ChromeMotionScope.of(context);
    switch (visibility) {
      case PanelVisibility$Showing(:final kind):
        final spec = motion.specOf(policy.showRole(kind));
        _curve = spec.curve;
        _motion.duration = spec.duration;
        _motion.forward().whenCompleteOrCancel(() => _settled(view));
      case PanelVisibility$Hiding(:final kind):
        final spec = motion.specOf(policy.hideRole(kind));
        _curve = spec.curve;
        _motion.reverseDuration = spec.duration;
        _motion.reverse().whenCompleteOrCancel(() => _settled(view));
      case PanelVisibility$Shown() || PanelVisibility$Hidden():
        break;
    }
  }

  void _settled(PanelStrategyContext view) {
    if (!_disposed) view.motionSettled();
  }

  void _restoreFocus() {
    final target = widget.strategy.composerFocus;
    if (target != null && _scope.hasFocus) {
      // The node under focus is about to leave the tree; hand focus over
      // after this frame so the move does not land in a teardown.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (target.context != null) target.requestFocus();
      });
    }
  }

  void _onPointerDown(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.mouse) _hover.touched();
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.strategy.style;
    final controller = _controller;
    final textDirection = Directionality.of(context);
    return Stack(
      children: [
        Positioned.fill(
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (event) => _hover.pressedOutside(event.position),
          ),
        ),
        Positioned.fill(
          child: ValueObservableBuilder<Rect?>(
            observable: controller.anchorRect,
            builder: (context, anchor) => ValueObservableBuilder<PanelWindow>(
              observable: controller.window,
              builder: (context, window) => LayoutBuilder(
                builder: (context, constraints) => CustomSingleChildLayout(
                  delegate: AnchoredPopupLayout(
                    width: style.width,
                    height: controller.policy.popupHeight(
                      windowHeight: window.height > 0
                          ? window.height
                          : constraints.maxHeight,
                    ),
                    textDirection: textDirection,
                    anchor: anchor,
                  ),
                  child: _popup(style),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _popup(AnchoredPopupStyle style) => MouseRegion(
    onEnter: (event) {
      if (event.kind == PointerDeviceKind.mouse) _hover.popupEntered();
    },
    onExit: (event) {
      if (event.kind == PointerDeviceKind.mouse) _hover.popupExited();
    },
    child: Listener(
      onPointerDown: _onPointerDown,
      child: AnimatedBuilder(
        animation: _motion,
        builder: (context, child) {
          final t = _curve.transform(_motion.value);
          return IgnorePointer(
            ignoring: widget.view.visibility.isHiding,
            child: Opacity(
              opacity: t.clamp(0.0, 1.0),
              child: Transform.scale(
                scale: style.scaleBegin + (1 - style.scaleBegin) * t,
                alignment: AlignmentDirectional.bottomEnd,
                child: child,
              ),
            ),
          );
        },
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(style.cornerRadius),
            boxShadow: style.shadows,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(style.cornerRadius),
            child: Shortcuts(
              shortcuts: AnchoredPopupShortcuts.standard,
              child: AnchoredPopupActions(
                controller: _controller,
                child: FocusScope(
                  node: _scope,
                  child: PanelShell(controller: _controller.shell),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
