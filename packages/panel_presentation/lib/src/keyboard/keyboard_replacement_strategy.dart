import 'dart:async';

import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:panel_presentation/src/ime/ime_input_port.dart';
import 'package:panel_presentation/src/keyboard/keyboard_height_store.dart';
import 'package:panel_presentation/src/keyboard/keyboard_nav_bar_fade.dart';
import 'package:panel_presentation/src/keyboard/keyboard_replacement_tuning.dart';
import 'package:panel_presentation/src/keyboard/keyboard_slot.dart';
import 'package:panel_presentation/src/keyboard/keyboard_slot_state.dart';
import 'package:panel_presentation/src/kind/panel_occupancy.dart';
import 'package:panel_presentation/src/kind/panel_presentation.dart';
import 'package:panel_presentation/src/kind/panel_visibility.dart';
import 'package:panel_presentation/src/policy/panel_window.dart';
import 'package:panel_presentation/src/strategy/panel_presentation_strategy.dart';
import 'package:panel_presentation/src/time/panel_clock.dart';
import 'package:panel_shell/panel_shell.dart';

/// The mobile strategy: the panel takes the place of the soft keyboard, in
/// flow, under the composer.
///
/// ## Ownership
///
/// **Owns:** the [KeyboardSlot] (the hand-off state machine, the animated
/// extent and the occupancy it publishes), the sheet that is laid out in the
/// slot, the bottom safe area and the scrim over it, and the panel's
/// expansion while search is open.
///
/// **Does not own:** the keyboard readings ([ImeInputPort], fed by the host),
/// the keyboard heights' storage ([KeyboardHeightStore]), the shell's page and
/// search state, or the host's layout (the host reserves a box of
/// [occupancy] height for the view and lifts the composer by it).
///
/// ## Contract with the host
///
/// * Feed every keyboard reading to the [ImeInputPort], with an honest
///   `animating` flag and the bottom safe area, and keep the window up to
///   date. The strategy reads no `MediaQuery` inset and no `SystemChannels`.
/// * Add [occupancy] into the viewport's bottom padding together with the
///   composer extent, and give the composer [composerSafeInset] as its
///   bottom safe area. The occupancy already contains the live keyboard.
/// * Dispose the strategy; the port, the store and the window stay with their
///   owners.
///
/// ## Occupancy while hidden
///
/// The occupancy follows the keyboard when the panel is not shown, so the
/// host reads one number whatever is in the slot.
final class KeyboardReplacementStrategy implements PanelPresentationStrategy {
  /// A strategy fed by [ime], remembering keyboard heights in [heights] and
  /// sizing against [window].
  ///
  /// [clock] schedules the cold-open delay and the hand-off fallback;
  /// [tuning] holds the default heights and the delays.
  KeyboardReplacementStrategy({
    required ImeInputPort ime,
    required KeyboardHeightStore heights,
    required ValueObservable<PanelWindow> window,
    PanelClock clock = PanelClock.system,
    KeyboardReplacementTuning tuning = const KeyboardReplacementTuning(),
  }) : _slot = KeyboardSlot(
         ime: ime,
         heights: heights,
         window: window,
         clock: clock,
         tuning: tuning,
       );

  final KeyboardSlot _slot;

  @override
  PanelPresentation get kind => const KeyboardReplacement();

  @override
  ValueObservable<PanelOccupancy> get occupancy => _slot.occupancy;

  /// Who holds the bottom slot: the keyboard alone, or the panel in one of
  /// its phases. A page that mounts paced content can skip the pacing while
  /// this is [KeyboardSlotState.replacing], when the panel is on screen at
  /// once.
  ValueObservable<KeyboardSlotState> get state => _slot.state;

  /// The part of the bottom safe area the occupancy has not covered yet; the
  /// composer's bottom safe area.
  ValueObservable<double> get composerSafeInset => _slot.composerSafeInset;

  /// Releases the slot and its listeners. Idempotent.
  void dispose() => _slot.dispose();

  @override
  Widget build(BuildContext context, PanelStrategyContext view) =>
      _KeyboardPanel(slot: _slot, view: view);
}

class _KeyboardPanel extends StatefulWidget {
  const _KeyboardPanel({required this.slot, required this.view});

  final KeyboardSlot slot;
  final PanelStrategyContext view;

  @override
  State<_KeyboardPanel> createState() => _KeyboardPanelState();
}

class _KeyboardPanelState extends State<_KeyboardPanel>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;

  /// The shell, built once per controller. Handing the same widget instance
  /// to every frame of the motion lets the framework skip the whole subtree:
  /// a frame costs the clip's layout and nothing under it.
  late Widget _shellView;
  var _last = Duration.zero;
  var _searchOpen = false;
  var _applying = false;

  KeyboardSlot get _slot => widget.slot;
  PanelShellController get _shell => widget.view.controller.shell;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _shellView = PanelShell(controller: _shell);
    _slot.animating.addListener(_onAnimating);
    _slot.state.addListener(_report);
    _slot.changes.addListener(_onChanged);
    _shell.search.addListener(_onSearch);
    _scheduleApply();
  }

  @override
  void didUpdateWidget(_KeyboardPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.view.controller.shell, _shell)) {
      oldWidget.view.controller.shell.search.removeListener(_onSearch);
      _shell.search.addListener(_onSearch);
      _shellView = PanelShell(controller: _shell);
    }
    if (oldWidget.view.visibility != widget.view.visibility) _scheduleApply();
  }

  @override
  void dispose() {
    _slot.animating.removeListener(_onAnimating);
    _slot.state.removeListener(_report);
    _slot.changes.removeListener(_onChanged);
    _shell.search.removeListener(_onSearch);
    _ticker.dispose();
    // Resetting signals observers, which must not happen while the tree is
    // being torn down.
    scheduleMicrotask(_slot.reset);
    super.dispose();
  }

  // --- Driving the slot -----------------------------------------------------

  /// Applies the visibility after the frame: the slot signals the host's
  /// listeners, which must not rebuild while this frame is building.
  void _scheduleApply() {
    if (_applying) return;
    _applying = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _applying = false;
      if (mounted) _apply();
    });
  }

  void _apply() {
    final motion = ChromeMotionScope.of(context);
    final slide = motion.specOf(MotionRole.listTransition);
    switch (widget.view.visibility) {
      case PanelVisibility$Showing():
        _slot.open(slide);
      case PanelVisibility$Shown():
        _slot.open(slide, animate: false);
      case PanelVisibility$Hiding(:final waitForIme):
        _slot.close(slide, waitForIme: waitForIme);
      case PanelVisibility$Hidden():
        break;
    }
    _syncSearch();
    _report();
  }

  void _onSearch() {
    if (_shell.search.value.isOpen != _searchOpen) _syncSearch();
  }

  void _syncSearch() {
    _searchOpen = _shell.search.value.isOpen;
    final media = MediaQuery.of(context);
    _slot.setSearch(
      open: _searchOpen,
      availableMax:
          media.size.height -
          media.viewPadding.top -
          _slot.safeBottom -
          _slot.tuning.searchReserve,
      spec: ChromeMotionScope.of(context).specOf(MotionRole.search),
    );
  }

  /// Tells the presentation controller that the motion it waits for is over.
  void _report() {
    final state = _slot.state.value;
    switch (widget.view.visibility) {
      case PanelVisibility$Showing() when state.isAtRest:
      case PanelVisibility$Hiding() when state is KeyboardSlotState$Idle:
        widget.view.motionSettled();
      case _:
        break;
    }
  }

  void _onAnimating() {
    if (_slot.animating.value) {
      _last = Duration.zero;
      if (!_ticker.isActive) unawaited(_ticker.start());
    } else if (_ticker.isActive) {
      _ticker.stop();
    }
  }

  void _onTick(Duration elapsed) {
    final step = elapsed - _last;
    _last = elapsed;
    _slot.advance(step);
  }

  void _onChanged() {
    if (!mounted) return;
    // A keyboard reading can arrive from the host's own build.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
  }

  // --- Drawing --------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final panel = ChromeThemeScope.panelOf(context);
    final safe = _slot.safeBottom;
    final height = _slot.layoutHeight > 0
        ? _slot.layoutHeight
        : _slot.restingHeight;
    final handingOff = _slot.state.value is KeyboardSlotState$HandOffToIme;

    // The sheet owns the bottom band: the keyboard no longer insets its
    // content and the safe area is the one the strategy was told about.
    return MediaQuery(
      data: media.copyWith(
        viewInsets: media.viewInsets.copyWith(bottom: 0),
        padding: media.padding.copyWith(bottom: safe),
        viewPadding: media.viewPadding.copyWith(bottom: safe),
      ),
      // The sheet is as tall as the panel, bottom-aligned, so a shorter box
      // clips its top instead of squeezing its content.
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.bottomCenter,
          minHeight: height,
          maxHeight: height,
          child: ColoredBox(
            color: panel.background,
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                // Emptied, not removed, while the keyboard takes over: the
                // sheet stays and the shell keeps its state.
                Offstage(offstage: handingOff, child: _shellView),
                if (safe > 0)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: KeyboardNavBarFade(
                      height: safe,
                      color: panel.background,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
