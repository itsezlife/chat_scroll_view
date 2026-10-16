import 'dart:async';
import 'dart:math' as math;

import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:listen/listen.dart' as listen;
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
import 'package:panel_presentation/src/view/listen_value_builder.dart';
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
/// entering it opens the popup at once (a click is the host's own
/// `PanelPresentationController.toggle`). The mouse leaving the toggle hides
/// it at the next event pass unless the pointer has entered the popup by
/// then, which it does when it crosses straight from one to the other: the
/// popup's hover area reaches down to the toggle, so there is no gap where
/// the pointer is over neither. Leaving the popup hides it after the policy's
/// leave delay (at once while it is still appearing), and entering it again,
/// even while it fades out, brings it back. A held auto-hide guard (an open
/// menu or variant picker, a page being dragged, a button pressed inside the
/// popup) defeats those delays; once the last hold is released with the
/// pointer away, the popup hides after the policy's after-hold delay. Nothing
/// else times a popup out. Touch and stylus never open or time out the
/// popup.
///
/// ## Dismissal and focus
///
/// A press outside the popup hides it, except on the toggle and on any
/// [AnchoredPopupExemptRegion] (the composer's input area, where the user
/// clicks back to keep typing). Escape steps back: the shell closes search
/// first, then the popup.
///
/// The popup never takes focus when it opens, however it was opened: the
/// composer keeps the caret, the search field is focused only by the user
/// clicking into it, and the panel is still reachable by Tab. Closing hands
/// focus back to [composerFocus] only if the popup held it (search was
/// focused).
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
  final _occupancy = listen.ValueNotifier<PanelOccupancy>(PanelOccupancy.zero);
  var _disposed = false;

  /// The pointer rules, shared with the toggle region.
  @internal
  PopupHover get hover => _hover;

  @override
  PanelPresentation get kind => const AnchoredPopup();

  @override
  listen.ValueListenable<PanelOccupancy> get occupancy => _occupancy;

  @override
  Widget build(BuildContext context, PanelStrategyContext view) =>
      _PopupBody(strategy: this, view: view);

  /// Stops the delays and releases the occupancy listenable. The controller
  /// and the shell are left to their owners. Idempotent.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _hover.dispose();
    _occupancy.dispose();
  }
}

/// Wraps the host's toggle so a mouse hovering it opens an anchored popup.
///
/// Only [PointerDeviceKind.mouse] counts: touch and stylus press it as a
/// click, which stays the host's own handler. A press by touch or stylus
/// marks the popup touch-driven, so it has no leave or after-hold delay
/// until a mouse hovers again. A press on the toggle never dismisses the
/// popup, and the popup's hover area reaches down to the toggle's top edge.
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
  var _inside = false;

  @override
  void initState() {
    super.initState();
    widget.strategy.hover.bind(widget.controller);
    _unregister = widget.strategy.hover.registerToggle(_bounds);
  }

  @override
  void dispose() {
    _unregister();
    // No exit is delivered to a region that leaves the tree under the pointer.
    if (_inside) widget.strategy.hover.toggleRemoved();
    super.dispose();
  }

  Rect? _bounds() => _globalBounds(context);

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (event) {
      if (event.kind == PointerDeviceKind.mouse) {
        _inside = true;
        widget.strategy.hover.toggleEntered(widget.controller);
      }
    },
    onExit: (event) {
      if (event.kind == PointerDeviceKind.mouse) {
        _inside = false;
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

/// Marks a region of the host's screen where a press does not dismiss an
/// anchored popup.
///
/// The composer's input area is one: a click back into it to keep typing is
/// not a click away from the popup. The press still reaches the child; this
/// only tells the popup not to treat it as outside. The toggle needs no such
/// wrapper, an [AnchoredPopupToggleRegion] is exempt already.
class AnchoredPopupExemptRegion extends StatefulWidget {
  /// A region around [child] that [strategy]'s popup does not dismiss on.
  const AnchoredPopupExemptRegion({
    required this.strategy,
    required this.child,
    super.key,
  });

  /// The strategy whose popup the region exempts.
  final AnchoredPopupStrategy strategy;

  /// What is exempt.
  final Widget child;

  @override
  State<AnchoredPopupExemptRegion> createState() =>
      _AnchoredPopupExemptRegionState();
}

class _AnchoredPopupExemptRegionState extends State<AnchoredPopupExemptRegion> {
  late void Function() _unregister;

  @override
  void initState() {
    super.initState();
    _unregister = widget.strategy.hover.registerExempt(_bounds);
  }

  @override
  void didUpdateWidget(AnchoredPopupExemptRegion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.strategy, widget.strategy)) {
      _unregister();
      _unregister = widget.strategy.hover.registerExempt(_bounds);
    }
  }

  @override
  void dispose() {
    _unregister();
    super.dispose();
  }

  Rect? _bounds() => _globalBounds(context);

  @override
  Widget build(BuildContext context) => widget.child;
}

Rect? _globalBounds(BuildContext context) {
  if (context.findRenderObject() case final RenderBox box
      when box.attached && box.hasSize) {
    return box.localToGlobal(Offset.zero) & box.size;
  }
  return null;
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
  final _regionKey = GlobalKey();
  PanelAutoHideHold? _dragHold;
  PanelAutoHideHold? _pressHold;
  final _pressedPointers = <int>{};
  late final StreamSubscription<PageScrollActivity> _scrollActivity;
  late final void Function() _unexemptRegion;
  Curve _curve = Curves.linear;
  // How far the hover area reaches below the popup, to touch the toggle.
  var _bridge = 0.0;
  var _bridgeScheduled = false;
  var _synced = false;
  var _disposed = false;

  PanelPresentationController get _controller => widget.view.controller;
  PopupHover get _hover => widget.strategy.hover;

  @override
  void initState() {
    super.initState();
    _hover.bind(_controller);
    // The hover area, shadow gutter and bridge included, is the popup's: a
    // press in it is not an outside press.
    _unexemptRegion = _hover.registerExempt(
      () => _globalBounds(_regionKey.currentContext ?? context),
    );
    _motion.value = widget.view.visibility.isShowing ? 0 : 1;
    _scrollActivity = _controller.shell.scrollActivity.listen(_onScroll);
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
    unawaited(_scrollActivity.cancel());
    _dragHold?.release();
    _dragHold = null;
    _pressHold?.release();
    _pressHold = null;
    _unexemptRegion();
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
    // A button pressed inside the popup (a scrollbar drag, a selection) is
    // finished by the pointer even if it leaves the popup on the way.
    _pressedPointers.add(event.pointer);
    _pressHold ??= _controller.holdAutoHide();
  }

  void _onPointerEnd(PointerEvent event) {
    if (!_pressedPointers.remove(event.pointer) ||
        _pressedPointers.isNotEmpty) {
      return;
    }
    _pressHold?.release();
    _pressHold = null;
  }

  // The hover area reaches down to the toggle. Where the toggle is is known
  // only after layout, so it is measured once a frame has laid out and only
  // rebuilt when it moved.
  void _scheduleBridge() {
    if (_bridgeScheduled) return;
    _bridgeScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _bridgeScheduled = false;
      if (_disposed || !mounted) return;
      final region = _globalBounds(_regionKey.currentContext ?? context);
      if (region == null) return;
      final gutter = widget.strategy.style.hoverGutter;
      final popupBottom = region.bottom - math.max(gutter, _bridge);
      var reach = 0.0;
      for (final toggle in _hover.toggleRects) {
        if (toggle.top >= popupBottom) {
          // A pixel into the toggle, so rounding cannot leave a seam.
          final needed = toggle.top - popupBottom + 1;
          reach = reach == 0 ? needed : math.min(reach, needed);
        }
      }
      if ((reach - _bridge).abs() > 0.5) setState(() => _bridge = reach);
    });
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
          child: ListenValueBuilder<Rect?>(
            listenable: controller.anchorRect,
            builder: (context, anchor) => ListenValueBuilder<PanelWindow>(
              listenable: controller.window,
              builder: (context, window) => LayoutBuilder(
                builder: (context, constraints) {
                  _scheduleBridge();
                  return CustomSingleChildLayout(
                    delegate: AnchoredPopupLayout(
                      width: style.width,
                      height: controller.policy.popupHeight(
                        windowHeight: window.height > 0
                            ? window.height
                            : constraints.maxHeight,
                      ),
                      textDirection: textDirection,
                      anchor: anchor,
                      outset: _outset(style),
                      gap: style.edgeGap,
                    ),
                    child: _popup(style),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  EdgeInsets _outset(AnchoredPopupStyle style) => EdgeInsets.fromLTRB(
    style.hoverGutter,
    style.hoverGutter,
    style.hoverGutter,
    math.max(style.hoverGutter, _bridge),
  );

  // Two regions: the outer one is the popup to the pointer, transparent
  // margin included, and lets what lies under the margin (the toggle, the
  // composer) take hits; the inner one is the card, which absorbs them. The
  // outer one is what enters and leaves.
  //
  // Both are in the text fields' tap group: on a desktop platform a field
  // gives up focus to a mouse press outside it, and a press on the panel is
  // not outside the composer it types into.
  Widget _popup(AnchoredPopupStyle style) =>
      TextFieldTapRegion(child: _hoverArea(style));

  Widget _hoverArea(AnchoredPopupStyle style) => MouseRegion(
    key: _regionKey,
    hitTestBehavior: HitTestBehavior.translucent,
    onEnter: (event) {
      if (event.kind == PointerDeviceKind.mouse) _hover.popupEntered();
    },
    onExit: (event) {
      if (event.kind == PointerDeviceKind.mouse) _hover.popupExited();
    },
    child: Padding(padding: _outset(style), child: _card(style)),
  );

  Widget _card(AnchoredPopupStyle style) => MouseRegion(
    child: Listener(
      onPointerDown: _onPointerDown,
      onPointerUp: _onPointerEnd,
      onPointerCancel: _onPointerEnd,
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
            // The composer's glass, so the panel over the chat reads as the
            // composer does.
            child: GlassSurface(
              material: GlassMaterial.composerIsland,
              cornerRadius: style.cornerRadius,
              child: Shortcuts(
                shortcuts: AnchoredPopupShortcuts.standard,
                child: AnchoredPopupActions(
                  controller: _controller,
                  child: FocusScope(
                    node: _scope,
                    child: PanelShell(
                      controller: _controller.shell,
                      arrangement: PanelArrangement.pointer,
                      background: const Color(0x00000000),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
