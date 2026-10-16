import 'dart:async';

import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:panel_presentation/src/docked/docked_style.dart';
import 'package:panel_presentation/src/kind/panel_occupancy.dart';
import 'package:panel_presentation/src/kind/panel_presentation.dart';
import 'package:panel_presentation/src/kind/panel_visibility.dart';
import 'package:panel_presentation/src/strategy/panel_presentation_strategy.dart';
import 'package:panel_shell/panel_shell.dart';

/// The **docked section** of desktop and web: the panel is a permanent
/// section at the reading end of the window, and the chat gives up its width.
///
/// Draws [Docked]. It mounts the controller's `PanelShell` in a section as
/// wide as [DockedStyle.width], full height, on the end edge of the box the
/// view fills (the left edge in a right-to-left layout). The section slides in
/// from that edge with the `panelSlide` role and slides back out.
///
/// ## Occupancy
///
/// The occupancy is the section's visible width on the inline-end axis, and
/// zero on the bottom axis. The host applies it in layout (for example as
/// end padding on the chat viewport), so the chat is never covered; it
/// follows the slide frame by frame, so the chat narrows as the section
/// arrives. The mounted view publishes it, because only a mounted view puts a
/// section on screen: with no view, or after the view leaves, it is zero.
///
/// ## What it leaves out
///
/// A docked section is permanent, so it has no hover, idle or outside-press
/// dismissal, and Escape only closes search. The user closes it with the
/// dock button (`PanelPresentationController.undock`) or the back intent.
/// Opening it does not take focus from the composer; focus inside it returns
/// to [composerFocus] when it closes.
///
/// The box the view fills must be bounded in both axes and at least
/// [DockedStyle.width] wide in a wide window, which is the only window the
/// policy docks in.
final class DockedStrategy implements PanelPresentationStrategy {
  /// A strategy drawing the section in [style].
  ///
  /// [composerFocus] is where focus goes back to when the section closes
  /// while it held focus; null leaves focus where the framework puts it.
  DockedStrategy({required this.style, this.composerFocus});

  /// How the section looks.
  final DockedStyle style;

  /// The composer's focus node, or null.
  final FocusNode? composerFocus;

  final _occupancy = ObservableValue<PanelOccupancy>(PanelOccupancy.zero);

  @override
  PanelPresentation get kind => const Docked();

  @override
  ValueObservable<PanelOccupancy> get occupancy => _occupancy;

  @override
  Widget build(BuildContext context, PanelStrategyContext view) =>
      _DockedBody(strategy: this, view: view);

  /// Releases the occupancy observable. The controller and the shell are left
  /// to their owners.
  void dispose() => _occupancy.dispose();
}

class _DockedBody extends StatefulWidget {
  const _DockedBody({required this.strategy, required this.view});

  final DockedStrategy strategy;
  final PanelStrategyContext view;

  @override
  State<_DockedBody> createState() => _DockedBodyState();
}

class _DockedBodyState extends State<_DockedBody>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(vsync: this);
  final _scope = FocusScopeNode(debugLabel: 'Docked');
  Curve _curve = Curves.linear;
  var _synced = false;
  var _disposed = false;

  DockedStrategy get _strategy => widget.strategy;
  double get _progress => _curve.transform(_motion.value).clamp(0.0, 1.0);

  @override
  void initState() {
    super.initState();
    _motion.value = widget.view.visibility.isShowing ? 0 : 1;
    _motion.addListener(_publish);
    if (_motion.value > 0) _publish();
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
  void didUpdateWidget(_DockedBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.view.visibility != widget.view.visibility) {
      if (widget.view.visibility.isHiding) _restoreFocus();
      _play();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _restoreFocus();
    _motion
      ..removeListener(_publish)
      ..dispose();
    _scope.dispose();
    // The section is off screen from here on. Zero is published after the
    // tree has finished unmounting, for the same reason as a late publish.
    final occupancy = _strategy._occupancy;
    scheduleMicrotask(() => occupancy.value = PanelOccupancy.zero);
    super.dispose();
  }

  // A host's listener may rebuild, which it must not do while the tree is
  // being built: a section that mounts already open, or whose motion is
  // instant, publishes after the frame instead. Ticks of a running motion
  // arrive before the build phase and publish at once.
  void _publish() {
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_disposed) _publish();
      });
      return;
    }
    _strategy._occupancy.value = PanelOccupancy(
      inlineEnd: _strategy.style.width * _progress,
    );
  }

  // Plays the motion for the visibility being shown, and reports its end.
  // A motion cancelled by a newer one reports too; the controller ignores a
  // report for a state that has been replaced.
  void _play() {
    final view = widget.view;
    final policy = view.controller.policy;
    final motion = ChromeMotionScope.of(context);
    switch (view.visibility) {
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
    final target = _strategy.composerFocus;
    if (target != null && _scope.hasFocus) {
      // The node under focus is about to leave the tree; hand focus over
      // after this frame so the move does not land in a teardown.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (target.context != null) target.requestFocus();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = _strategy.style;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return ClipRect(
      child: Align(
        alignment: AlignmentDirectional.centerEnd,
        child: AnimatedBuilder(
          animation: _motion,
          builder: (context, child) => FractionalTranslation(
            // Away from the end edge by the share not yet slid in.
            translation: Offset((rtl ? -1 : 1) * (1 - _progress), 0),
            child: child,
          ),
          child: IgnorePointer(
            ignoring: widget.view.visibility.isHiding,
            child: SizedBox(
              width: style.width,
              height: double.infinity,
              child: DecoratedBox(
                position: DecorationPosition.foreground,
                decoration: BoxDecoration(
                  border: switch (style.separator) {
                    final separator? => BorderDirectional(
                      start: BorderSide(color: separator),
                    ),
                    null => null,
                  },
                ),
                child: FocusScope(
                  node: _scope,
                  child: PanelShell(controller: widget.view.controller.shell),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
