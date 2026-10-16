import 'dart:math' as math;

import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/animation.dart' show Curves;
import 'package:listen/listen.dart' as listen;
import 'package:meta/meta.dart';
import 'package:panel_presentation/src/ime/ime_input_port.dart';
import 'package:panel_presentation/src/ime/ime_sample.dart';
import 'package:panel_presentation/src/keyboard/keyboard_height_store.dart';
import 'package:panel_presentation/src/keyboard/keyboard_replacement_tuning.dart';
import 'package:panel_presentation/src/keyboard/keyboard_slot_state.dart';
import 'package:panel_presentation/src/kind/panel_occupancy.dart';
import 'package:panel_presentation/src/policy/panel_window.dart';
import 'package:panel_presentation/src/time/panel_clock.dart';

/// The bottom slot of the window, shared by the soft keyboard and the panel
/// that replaces it: the **hand-off state machine** of the keyboard-replacement
/// presentation, with the animated extent it publishes.
///
/// ## Ownership
///
/// **Owns:** the sealed [KeyboardSlotState], the animated panel extent, the
/// bottom space published as [occupancy], the safe-area band left to the
/// composer ([composerSafeInset]) and the fallback timeout of a hand-off to
/// the keyboard.
///
/// **Does not own:** drawing (the strategy does), the clock of animation
/// frames (the strategy's view forwards elapsed time to [advance]), the
/// panel's page or search state, or where the keyboard readings come from
/// (the [ImeInputPort]).
///
/// ## Occupancy
///
/// The published bottom space is always `max(keyboard, panel extent)`: the
/// keyboard and the panel share the slot instead of taking turns, so a
/// keyboard that collapses beneath a panel that just replaced it, or that
/// glitches to zero and back, changes nothing. It includes the bottom safe
/// area, as the keyboard height does, and so the panel extent is its content
/// height plus the safe area.
///
/// ## Hand-offs
///
/// * **Keyboard to panel** ([open] with the keyboard up): the panel takes the
///   slot at once, at least as tall as the keyboard ([KeyboardSlotState.replacing]).
/// * **Panel to keyboard** ([close] with `waitForIme`): the panel keeps the
///   slot, emptied, until the keyboard reports a *settled* reading, a sample
///   whose `animating` is false and whose height is up
///   ([KeyboardSlotState.handOffToIme]). Samples that are animating never
///   release it, which is what makes a keyboard's transient zeros and
///   spikes harmless without counting samples or reading the wall clock.
///   When no such reading arrives within [KeyboardReplacementTuning.handOffTimeout]
///   the panel closes cold.
///
/// Hosts must therefore report `animating` honestly: a sample that claims to
/// be settled is taken at its word.
///
/// ## Time
///
/// All motion is driven by [advance]; all waiting by the [PanelClock]. Nothing
/// here reads a ticker or `DateTime.now`.
final class KeyboardSlot {
  /// A slot fed by [ime], measured against [window], remembering keyboard
  /// heights in [heights].
  KeyboardSlot({
    required ImeInputPort ime,
    required KeyboardHeightStore heights,
    required listen.ValueListenable<PanelWindow> window,
    required PanelClock clock,
    this.tuning = const KeyboardReplacementTuning(),
  }) : _ime = ime,
       _heights = heights,
       _window = window,
       _clock = clock {
    _sample = ime.samples.value;
    _orientation = _orientationOf(window.value);
    _ime.samples.addListener(_onSample);
    _window.addListener(_onWindow);
    _publish();
  }

  /// The numbers the slot is tuned with.
  final KeyboardReplacementTuning tuning;

  final ImeInputPort _ime;
  final KeyboardHeightStore _heights;
  final listen.ValueListenable<PanelWindow> _window;
  final PanelClock _clock;

  final _state = listen.ValueNotifier<KeyboardSlotState>(
    KeyboardSlotState.idle,
  );
  final _occupancy = listen.ValueNotifier<PanelOccupancy>(PanelOccupancy.zero);
  final _composerSafeInset = listen.ValueNotifier<double>(0);
  final _animating = listen.ValueNotifier<bool>(false);
  final _changes = _ChangeSignal();

  late ImeSample _sample;
  late PanelOrientation _orientation;

  /// The panel's content height at rest, without the safe area and without
  /// the search expansion.
  double _base = 0;

  /// The content height while search is open, or null.
  double? _expanded;

  /// The animated panel extent, safe area included.
  double _extent = 0;

  /// The sheet height held while the extent grows or shrinks, or null.
  double? _fixedLayout;

  /// The height the keyboard is held at after a hand-off, or 0.
  double _sticky = 0;

  _Tween? _tween;
  var _delayed = false;
  PanelTimer? _delayTimer;
  PanelTimer? _handOffTimer;
  MotionSpec _closeSpec = const MotionSpec(Duration.zero, Curves.linear);
  var _disposed = false;

  // --- Published ------------------------------------------------------------

  /// Who holds the slot, and in which phase.
  listen.ValueListenable<KeyboardSlotState> get state => _state;

  /// The space taken at the bottom of the window: the larger of the keyboard
  /// and the panel, safe area included. [PanelOccupancy.inlineEnd] is always
  /// zero.
  listen.ValueListenable<PanelOccupancy> get occupancy => _occupancy;

  /// The part of the bottom safe area the occupancy has not covered yet: what
  /// the composer still pads itself with.
  ///
  /// `max(0, safeBottom - occupancy.bottom)`, so the bottom of the window is
  /// `max(safeBottom, occupancy)` throughout, with no step and no double
  /// count.
  listen.ValueListenable<double> get composerSafeInset => _composerSafeInset;

  /// Whether a motion is running, and so whether [advance] should be called
  /// every frame. False while a cold open waits for its start delay.
  listen.ValueListenable<bool> get animating => _animating;

  /// Signals whenever the extent, the state or the layout height changed.
  listen.Listenable get changes => _changes;

  /// The height the sheet is laid out at: fixed while the slot grows or
  /// shrinks, so the content never reflows mid-motion, and equal to the
  /// extent while search expands or collapses it.
  double get layoutHeight => _fixedLayout ?? _extent;

  /// The height the sheet would open at now, for laying it out before the
  /// first motion.
  double get restingHeight =>
      (_state.value.holdsSlot ? _contentTarget : _resolveBase()) + safeBottom;

  /// The bottom safe area, as the latest reading reports it.
  double get safeBottom => _sample.safeAreaBottom;

  /// Whether the latest reading has the soft keyboard up (animating or not):
  /// the condition under which [open] replaces the keyboard instead of
  /// growing into a free slot.
  bool get keyboardIsUp => _keyboardUp;

  // --- Intents --------------------------------------------------------------

  /// Takes the slot for the panel.
  ///
  /// With the keyboard up the panel claims the slot at once and is
  /// [KeyboardSlotState.replacing]. Otherwise it grows from where the slot is
  /// over [spec]: from nothing after the cold-open delay, or from the current
  /// extent when it turns a close or a hand-off back. A zero-duration [spec]
  /// or `animate: false` lands [KeyboardSlotState.open] at once. Does nothing
  /// when the panel already holds the slot.
  void open(MotionSpec spec, {bool animate = true}) {
    if (_disposed) return;
    final current = _state.value;
    if (current
        case KeyboardSlotState$Open() ||
            KeyboardSlotState$Replacing() ||
            KeyboardSlotState$Opening()) {
      return;
    }
    _cancelTimers();
    _sticky = 0;
    if (current case KeyboardSlotState$Idle()) {
      _base = _resolveBase();
      _expanded = null;
    }
    final goal = _contentTarget + safeBottom;
    if (_keyboardUp) {
      _land(KeyboardSlotState.replacing, goal);
    } else if (!animate || spec.duration == Duration.zero) {
      _land(KeyboardSlotState.open, goal);
    } else if (current case KeyboardSlotState$Idle()) {
      _extent = 0;
      _fixedLayout = goal;
      _state.value = KeyboardSlotState.opening;
      _delayed = tuning.coldOpenDelay > Duration.zero;
      if (_delayed) {
        _delayTimer = _clock.after(tuning.coldOpenDelay, _startMotion);
      }
      _retarget(goal, spec);
    } else if (_extent >= goal - _epsilon) {
      _land(KeyboardSlotState.open, goal);
    } else {
      _fixedLayout = goal;
      _state.value = KeyboardSlotState.opening;
      _retarget(goal, spec);
    }
    _publish();
  }

  /// Gives the slot back.
  ///
  /// With [waitForIme] the panel keeps the slot, emptied, until the keyboard
  /// has risen to take it (see the class documentation), so the composer does
  /// not drop and rise again; a keyboard that is already up takes it at once.
  /// Otherwise the panel shrinks to nothing over [spec]. Closing also ends the
  /// search expansion. Does nothing for an idle slot, a slot already closing
  /// or a hand-off that is already waiting.
  void close(MotionSpec spec, {bool waitForIme = false}) {
    if (_disposed) return;
    final current = _state.value;
    final nothingToClose = switch (current) {
      KeyboardSlotState$Idle() || KeyboardSlotState$Closing() => true,
      KeyboardSlotState$HandOffToIme() => waitForIme,
      KeyboardSlotState$Opening() ||
      KeyboardSlotState$Replacing() ||
      KeyboardSlotState$Open() => false,
    };
    if (nothingToClose) return;
    _cancelTimers();
    _expanded = null;
    if (waitForIme) {
      if (_keyboardSettledUp) {
        _handOver();
      } else {
        _state.value = KeyboardSlotState.handOffToIme;
        _fixedLayout = null;
        _closeSpec = spec;
        _retarget(_base + safeBottom, spec);
        _handOffTimer = _clock.after(tuning.handOffTimeout, _handOffTimedOut);
      }
    } else {
      _beginClose(spec);
    }
    _publish();
  }

  /// Grows the panel for search, or shrinks it back.
  ///
  /// The panel grows by [KeyboardReplacementTuning.searchExpansion], but never
  /// beyond [availableMax] (the content height the window leaves) and never
  /// below its keyboard-sized height; a non-finite or non-positive
  /// [availableMax] means the space is unknown and the full expansion
  /// applies. Ignored unless the panel is opening or at rest.
  void setSearch({
    required bool open,
    required double availableMax,
    required MotionSpec spec,
  }) {
    if (_disposed) return;
    final current = _state.value;
    if (current
        case KeyboardSlotState$Idle() ||
            KeyboardSlotState$Closing() ||
            KeyboardSlotState$HandOffToIme()) {
      return;
    }
    final before = _expanded;
    if (open) {
      final cap = availableMax.isFinite && availableMax > 0
          ? availableMax
          : _base + tuning.searchExpansion;
      _expanded = math.max(
        _base,
        math.min(cap, _base + tuning.searchExpansion),
      );
    } else {
      _expanded = null;
    }
    if (_expanded == before) return;
    final goal = _contentTarget + safeBottom;
    if (current case KeyboardSlotState$Opening()) _fixedLayout = goal;
    _retarget(goal, spec);
    _publish();
  }

  /// Moves the running motion forward by [elapsed]. Does nothing unless
  /// [animating].
  void advance(Duration elapsed) {
    final tween = _tween;
    if (_disposed || tween == null || _delayed) return;
    final next = tween.advanced(elapsed);
    _extent = next.value;
    if (next.done) {
      _finishTween();
    } else {
      _tween = next;
    }
    _syncAnimating();
    _publish();
  }

  /// Puts the slot back to the keyboard alone, cancelling every motion and
  /// timer. For a view that went away.
  void reset() {
    if (_disposed) return;
    _cancelTimers();
    _tween = null;
    _delayed = false;
    _extent = 0;
    _fixedLayout = null;
    _expanded = null;
    _sticky = 0;
    _state.value = KeyboardSlotState.idle;
    _syncAnimating();
    _publish();
  }

  /// Stops listening and drops every observer and timer. Idempotent.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _cancelTimers();
    _ime.samples.removeListener(_onSample);
    _window.removeListener(_onWindow);
    _state.dispose();
    _occupancy.dispose();
    _composerSafeInset.dispose();
    _animating.dispose();
    _changes.dispose();
  }

  // --- Inputs ---------------------------------------------------------------

  void _onSample() {
    if (_disposed) return;
    final before = _sample;
    _sample = _ime.samples.value;
    switch (_state.value) {
      case KeyboardSlotState$HandOffToIme() when _keyboardSettledUp:
        _handOver();
      case KeyboardSlotState$Replacing() when _keyboardSettledGone:
        _state.value = KeyboardSlotState.open;
      case _:
        break;
    }
    if (_state.value case KeyboardSlotState$Idle()) _measure();
    _updateSticky();
    if (_sample.safeAreaBottom != before.safeAreaBottom) _refreshGoal();
    _publish();
  }

  void _onWindow() {
    if (_disposed) return;
    final next = _orientationOf(_window.value);
    if (next == _orientation) return;
    _orientation = next;
    final current = _state.value;
    if (current case KeyboardSlotState$Idle() || KeyboardSlotState$Closing()) {
      return;
    }
    final grown = (_expanded ?? _base) - _base;
    _base = _resolveBase();
    if (_expanded != null) _expanded = _base + grown;
    _refreshGoal();
    _publish();
  }

  // --- Transitions ----------------------------------------------------------

  /// Hands the slot to the keyboard that has risen.
  void _handOver() {
    final floor = _base + safeBottom;
    _cancelTimers();
    _tween = null;
    _extent = 0;
    _fixedLayout = null;
    _sticky = _sample.height >= floor - tuning.settleTolerance ? floor : 0;
    _state.value = KeyboardSlotState.idle;
    _syncAnimating();
    _measure();
  }

  void _handOffTimedOut() {
    _handOffTimer = null;
    if (_state.value case KeyboardSlotState$HandOffToIme()) {
      _beginClose(_closeSpec);
      _publish();
    }
  }

  void _beginClose(MotionSpec spec) {
    _fixedLayout = layoutHeight;
    _state.value = KeyboardSlotState.closing;
    _retarget(0, spec);
  }

  void _land(KeyboardSlotState state, double extent) {
    _tween = null;
    _delayed = false;
    _extent = extent;
    _fixedLayout = null;
    _state.value = state;
    _syncAnimating();
  }

  void _startMotion() {
    _delayTimer = null;
    _delayed = false;
    _syncAnimating();
    _publish();
  }

  /// Aims the extent at [to] over [spec], from where it is.
  void _retarget(double to, MotionSpec spec) {
    if (spec.duration == Duration.zero || (to - _extent).abs() < _epsilon) {
      _extent = to;
      _tween = null;
      _finishTween();
    } else {
      _tween = _Tween(from: _extent, to: to, spec: spec);
    }
    _syncAnimating();
  }

  void _finishTween() {
    _tween = null;
    switch (_state.value) {
      case KeyboardSlotState$Opening():
        _fixedLayout = null;
        _delayed = false;
        _delayTimer?.cancel();
        _delayTimer = null;
        _state.value = _keyboardUp
            ? KeyboardSlotState.replacing
            : KeyboardSlotState.open;
      case KeyboardSlotState$Closing():
        _extent = 0;
        _fixedLayout = null;
        _state.value = KeyboardSlotState.idle;
      case _:
        break;
    }
  }

  /// Re-aims at the goal of the current state after the target changed under
  /// it (a rotation, a new safe area): a running motion is re-pointed, a
  /// resting panel snaps.
  void _refreshGoal() {
    final current = _state.value;
    if (!current.holdsSlot) return;
    if (current case KeyboardSlotState$Closing()) return;
    final goal = switch (current) {
      KeyboardSlotState$HandOffToIme() => _base + safeBottom,
      _ => _contentTarget + safeBottom,
    };
    final tween = _tween;
    if (tween != null) {
      _tween = _Tween(from: _extent, to: goal, spec: tween.spec);
      if (current case KeyboardSlotState$Opening()) _fixedLayout = goal;
    } else {
      _extent = goal;
    }
  }

  // --- Derived --------------------------------------------------------------

  double get _contentTarget => _expanded ?? _base;

  bool get _keyboardUp => _sample.height > tuning.settleTolerance;

  bool get _keyboardSettledUp => _keyboardUp && !_sample.animating;

  bool get _keyboardSettledGone =>
      _sample.height <= tuning.settleTolerance && !_sample.animating;

  double get _imeContent =>
      _keyboardUp ? math.max(0, _sample.height - safeBottom) : 0;

  double _resolveBase() => math.max(
    _heights.heightFor(_orientation) ??
        tuning.defaultHeightFor(_window.value.windowClass),
    _imeContent,
  );

  static PanelOrientation _orientationOf(PanelWindow window) =>
      window.width > window.height
      ? PanelOrientation.landscape
      : PanelOrientation.portrait;

  /// Remembers a settled keyboard as the height to open the panel at.
  void _measure() {
    if (_sample.animating || !_keyboardUp) return;
    // The store drops what is not a keyboard; it never throws.
    _heights.record(_orientation, _sample.height - safeBottom);
  }

  /// Ends the hold on a height once the keyboard has left it by more than the
  /// tolerance.
  void _updateSticky() {
    if (_sticky > 0 && _sample.height < _sticky - tuning.settleTolerance) {
      _sticky = 0;
    }
  }

  void _syncAnimating() {
    _animating.value = _tween != null && !_delayed;
  }

  void _cancelTimers() {
    _delayTimer?.cancel();
    _delayTimer = null;
    _handOffTimer?.cancel();
    _handOffTimer = null;
    _delayed = false;
  }

  void _publish() {
    final keyboard = math.max(_sample.height, _sticky);
    final bottom = math.max(keyboard, _extent);
    _occupancy.value = PanelOccupancy(bottom: bottom);
    _composerSafeInset.value = math.max(0, safeBottom - bottom);
    _changes.signal();
  }

  static const double _epsilon = 0.01;
}

/// One running extent animation: from, to and how long it has run.
@immutable
final class _Tween {
  const _Tween({
    required this.from,
    required this.to,
    required this.spec,
    this.elapsed = Duration.zero,
  });

  final double from;
  final double to;
  final MotionSpec spec;
  final Duration elapsed;

  bool get done => elapsed >= spec.duration;

  double get value {
    if (done) return to;
    final t = elapsed.inMicroseconds / spec.duration.inMicroseconds;
    return from + (to - from) * spec.curve.transform(t);
  }

  _Tween advanced(Duration by) =>
      _Tween(from: from, to: to, spec: spec, elapsed: elapsed + by);
}

/// The signal behind [KeyboardSlot.changes]: `notifyListeners` is protected,
/// so the slot reaches it through this subclass.
final class _ChangeSignal extends listen.ChangeNotifier {
  void signal() => notifyListeners();
}
