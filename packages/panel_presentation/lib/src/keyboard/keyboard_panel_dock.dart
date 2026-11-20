import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:listen/listen.dart' as listen;
import 'package:panel_presentation/src/controller/panel_presentation_controller.dart';
import 'package:panel_presentation/src/keyboard/keyboard_replacement_strategy.dart';
import 'package:panel_presentation/src/kind/panel_presentation.dart';
import 'package:panel_presentation/src/kind/panel_visibility.dart';

/// The text field a panel replaces the soft keyboard of, as the dock sees
/// it: its focus, whether its soft keyboard is held back, and a request for
/// the keyboard. A host adapts its field (a composer) to it.
abstract interface class KeyboardPanelField {
  /// Whether the field has the focus.
  bool get hasFocus;

  /// Holds the field's soft keyboard back ([held]) while a panel stands in
  /// its place, the focus and caret staying; or lets it come again.
  void holdKeyboardBack({required bool held});

  /// Asks for the soft keyboard (focusing the field if it needs to).
  void requestKeyboard();
}

/// The swap between a field's soft keyboard and the panel that replaces it:
/// the panel button, the hand-off back to the keyboard, the field's taps
/// while the panel is up, and back during a hand-off.
///
/// It drives a [PanelPresentationController] whose panel is presented by a
/// [KeyboardReplacementStrategy]; the occupancy, the slot's motion and the
/// field's safe-area pad are the strategy's. Every behaviour here acts only
/// while that kind is the one shown; a host with other kinds (a popup, a
/// dock) handles those itself.
///
/// The rules:
///
/// - While the panel is coming or on screen in the keyboard's place, the
///   field's soft keyboard is held back, and a keyboard that is up goes
///   down ([hideKeyboard]): focus stays in the field.
/// - The button (or a tap on the field) gives the place back to the
///   keyboard: the keyboard is asked for first, search closes and settles,
///   and the panel keeps its place, emptied, until the keyboard has risen
///   (`hide(waitForIme: true)`), so nothing jumps.
/// - Pressed again during that hand-off, the panel stays and the keyboard
///   goes back down.
/// - Back during a hand-off ends it at once: the keyboard on its way up
///   goes down, the panel closes from where it is.
final class KeyboardPanelDock {
  /// A dock over [presentation], whose keyboard-replacement strategy is
  /// [keyboard], for [field]; [hideKeyboard] lowers the soft keyboard, with
  /// the reason (for a log).
  KeyboardPanelDock({
    required this.presentation,
    required this.keyboard,
    required this.field,
    required Future<void> Function(String why) hideKeyboard,
  }) : _hideKeyboard = hideKeyboard {
    presentation.state.addListener(_onState);
    _onState();
  }

  /// The presentation this dock drives.
  final PanelPresentationController presentation;

  /// The strategy that puts the panel in the keyboard's place.
  final KeyboardReplacementStrategy keyboard;

  /// The field whose keyboard the panel replaces.
  final KeyboardPanelField field;

  final Future<void> Function(String why) _hideKeyboard;
  final _leaving = listen.ValueNotifier<bool>(false);
  var _handOffRun = 0;
  var _armedForTap = false;
  var _wasReplacing = false;
  var _disposed = false;

  /// True from a hand-off to the keyboard until the panel hides.
  listen.ValueListenable<bool> get leavingForKeyboard => _leaving;

  /// Whether the panel is coming or on screen in the keyboard's place.
  bool get panelInKeyboardPlace =>
      switch (presentation.state.value) {
        PanelVisibility$Showing() || PanelVisibility$Shown() => true,
        _ => false,
      } &&
      presentation.state.value.kind is KeyboardReplacement;

  /// Whether the panel replaces the keyboard now, not leaving for it.
  bool get panelReplacesKeyboard => panelInKeyboardPlace && !_leaving.value;

  /// Whether the panel is giving its place to the keyboard: search
  /// shrinking back first, or the emptied panel waiting for the keyboard.
  bool get handingOff =>
      _leaving.value ||
      switch (presentation.state.value) {
        PanelVisibility$Hiding(:final waitForIme) => waitForIme,
        _ => false,
      };

  /// The panel button: shows the panel in the keyboard's place; on screen,
  /// gives the place back to the keyboard; pressed again during that
  /// hand-off, the panel stays.
  void toggle() {
    if (_disposed) return;
    if (panelInKeyboardPlace) {
      if (_leaving.value) {
        _stayOnPanel();
      } else {
        handOffToKeyboard();
      }
      return;
    }
    presentation.show(kind: const KeyboardReplacement());
  }

  /// A tap on the field: back to the keyboard while the panel replaces it.
  void onFieldTap() {
    if (_disposed) return;
    if (panelReplacesKeyboard) handOffToKeyboard();
  }

  /// A pointer went down on the field. While the panel replaces the
  /// keyboard the hold is lifted at once, before the tap brings focus: the
  /// field then attaches with a keyboard type.
  void onFieldPointerDown() {
    if (_disposed || !panelReplacesKeyboard) return;
    _armedForTap = true;
    field.holdKeyboardBack(held: false);
  }

  /// The pointer on the field lifted or was cancelled: a tap hands off in
  /// the same event; anything else puts the hold back.
  void onFieldPointerEnd() {
    if (!_armedForTap) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed || !_armedForTap) return;
      _armedForTap = false;
      if (panelReplacesKeyboard) field.holdKeyboardBack(held: true);
    });
  }

  /// Gives the place back to the soft keyboard: the keyboard is asked for,
  /// search closes and settles, and the panel keeps its place, emptied,
  /// until the keyboard has risen.
  void handOffToKeyboard() {
    if (_disposed || _leaving.value) return;
    _leaving.value = true;
    _armedForTap = false;
    unawaited(_handOff(++_handOffRun));
  }

  /// Back while the panel hands its place to the keyboard: the hand-off
  /// ends, the keyboard on its way up goes down and the panel closes from
  /// where it is. False when no hand-off is under way.
  bool backDuringHandOff() {
    if (_disposed || !handingOff) return false;
    _handOffRun++;
    _leaving.value = false;
    unawaited(_hideKeyboard('back during the hand-off'));
    presentation.shell.closeSearch();
    presentation.handleBack();
    return true;
  }

  Future<void> _handOff(int run) async {
    bool superseded() => _disposed || run != _handOffRun;
    try {
      // Asked for here and only here, so a panel closed any other way
      // (back) leaves the keyboard down.
      field
        ..holdKeyboardBack(held: false)
        ..requestKeyboard();
      final shell = presentation.shell;
      if (shell.search.value.isOpen) {
        await _waitFrames(until: () => field.hasFocus || superseded());
        if (superseded()) return;
        shell.closeSearch();
        await _slotAtRest();
        if (superseded()) return;
      }
      // Back, or another close, may have taken the panel away meanwhile.
      if (!panelInKeyboardPlace) return;
      presentation.hide(waitForIme: true);
    } finally {
      if (!superseded()) _leaving.value = false;
    }
  }

  void _stayOnPanel() {
    _handOffRun++;
    _leaving.value = false;
    field.holdKeyboardBack(held: true);
    _lowerKeyboardForPanel();
  }

  static Future<void> _waitFrames({required bool Function() until}) async {
    for (var i = 0; i < 4 && !until(); i++) {
      await SchedulerBinding.instance.endOfFrame;
    }
  }

  // Completes once the keyboard slot stopped moving, or after a second.
  Future<void> _slotAtRest() {
    final animating = keyboard.animating;
    if (!animating.value) return Future<void>.value();
    final done = Completer<void>();
    void check() {
      if (animating.value || done.isCompleted) return;
      animating.removeListener(check);
      done.complete();
    }

    animating.addListener(check);
    return done.future.timeout(
      const Duration(seconds: 1),
      onTimeout: () => animating.removeListener(check),
    );
  }

  void _onState() {
    if (_disposed) return;
    final replacing = panelReplacesKeyboard;
    // Also when it turns back while hiding: the keyboard its hand-off asked
    // for is on its way up and goes down again.
    if (replacing && !_wasReplacing) _lowerKeyboardForPanel();
    _wasReplacing = replacing;
    field.holdKeyboardBack(held: replacing);
  }

  // A keyboard that is up when the panel takes its place goes down, and
  // focus stays in the field. Holding the keyboard back keeps the next
  // focus from raising one; it does not lower the one showing.
  void _lowerKeyboardForPanel() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // A press in the same frame may have asked for the keyboard again.
      if (_disposed || !panelReplacesKeyboard) return;
      unawaited(_hideKeyboard("the panel took the keyboard's place"));
    });
  }

  /// Stops listening. Idempotent.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    presentation.state.removeListener(_onState);
    _leaving.dispose();
  }
}
