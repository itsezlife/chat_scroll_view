import 'dart:async';
import 'dart:ui' show Rect;

import 'package:content_model/content_model.dart';
import 'package:flutter/foundation.dart';
import 'package:listen/listen.dart' as listen;
import 'package:panel_presentation/src/docked/dock_width_store.dart';
import 'package:panel_presentation/src/kind/panel_occupancy.dart';
import 'package:panel_presentation/src/kind/panel_presentation.dart';
import 'package:panel_presentation/src/kind/panel_visibility.dart';
import 'package:panel_presentation/src/policy/panel_os_family.dart';
import 'package:panel_presentation/src/policy/panel_presentation_policy.dart';
import 'package:panel_presentation/src/policy/panel_window.dart';
import 'package:panel_presentation/src/strategy/panel_presentation_strategy.dart';
import 'package:panel_shell/panel_shell.dart';

/// The host-facing controller that owns the panel's **visibility**: whether
/// it is on screen, as which [PanelPresentation] kind, and how much space
/// that takes.
///
/// ## Ownership
///
/// **Owns:** the sealed [PanelVisibility] state, the window the policy sizes
/// against, the dock preference, the anchor rectangle, the auto-hide guard,
/// the published [occupancy], and the report of presence to the shell.
///
/// **Does not own:** the selected page, the search state or the pages'
/// controllers (the wrapped [shell] does, which is why they survive a switch
/// of kind), the drawing of any kind (a [PanelPresentationStrategy] does),
/// the composer, or the store that keeps the dock preference (the host owns
/// the [PreferenceStore]; the controller reads and writes it through the seam).
///
/// ## Intents
///
/// [show], [hide], [toggle], [handleBack], [anchor], [dock], [undock] and
/// [toggleDock] and [updateWindow] are the only ways to change the state. Intents that change
/// nothing are silent, and after [dispose] every intent is a no-op.
///
/// ## Commit when unbound
///
/// Intents commit whether or not a view is mounted. With no view attached
/// there is no motion to wait for, so [show] lands in `shown` and [hide] in
/// `hidden` at once; with a view attached they enter `showing` or `hiding`
/// and the view settles them through [attach]. Detaching the last view
/// settles whatever is moving, so a state never waits for motion that no one
/// plays.
///
/// ## The dock
///
/// A dock is a **standing section**, as in the reference client: while the
/// user prefers it ([dockPreferred]) and the window has room for it
/// (`PanelPresentationPolicy.canDock`) it is on screen, shown by the window
/// and not by a click or a hover. The preference is the user's, the window is
/// the host's, and the dock is what both allow: a window that narrows below
/// the room takes the dock away (the panel is hidden, not turned into a
/// popup, and the preference stays), a window that widens again brings it
/// back, and turning the preference off closes it. A dock cannot be dismissed
/// by back or Escape (see `PanelPresentationPolicy.dismissalsFor`).
///
/// Its width is the user's too: [resizeDock] follows a drag and [endDockResize]
/// keeps where it ended, in the [DockWidthStore] when there is one. What is
/// kept is the wish ([dockWanted]); the width a dock has in a window is the
/// policy's (`dockWidthIn`), so a window that widens gives the wish back.
///
/// ## Dock preference
///
/// With a [PreferenceStore] the controller starts from its `dockPreferred`,
/// writes every [dock] and [undock] to it, and follows a change made by
/// anyone else (another window sharing the store): the store is the truth,
/// [dockPreferred] its mirror. A failed write is reported to
/// [FlutterError.reportError] and never thrown into an intent; the choice
/// stays in memory and the next successful write persists it. Without a store
/// the preference lives in memory, seeded by the constructor.
///
/// ## Shell
///
/// The controller wraps [shell] without owning it: it reports presence to it
/// ([PanelShellController.updatePresence]) after every change of visibility
/// and turns every shell event (a page change, search opening or closing, a
/// pick) into a signal on [interactions]. [handleBack] steps back through the
/// shell first.
///
/// ## Holds
///
/// [holdAutoHide] is the one seam through which something keeps a
/// self-dismissing presentation open: an open menu or variant picker, a drag.
/// Search focus is deliberately not a hold; see [autoHideGuard].
final class PanelPresentationController {
  /// Creates a controller over [shell].
  ///
  /// [policy] defaults to the one for the OS family the app runs on.
  /// [strategies] draw the kinds; a kind without one is never drawn and takes
  /// no space. [window] seeds the window the policy sizes against.
  ///
  /// [preferences], when given, is the source of the dock choice: its
  /// `dockPreferred` wins over the [dockPreferred] flag, which only seeds a
  /// controller that has no store.
  ///
  /// [dockWidths], when given, is where the width the user drags the dock to is
  /// kept; the controller starts from it.
  ///
  /// Throws an [ArgumentError] for two strategies of one kind.
  factory PanelPresentationController({
    required PanelShellController shell,
    PanelPresentationPolicy? policy,
    List<PanelPresentationStrategy> strategies = const [],
    PanelWindow window = const PanelWindow(width: 0, height: 0),
    bool dockPreferred = false,
    PreferenceStore? preferences,
    DockWidthStore? dockWidths,
  }) {
    final byKind = <PanelPresentation, PanelPresentationStrategy>{};
    for (final strategy in strategies) {
      if (byKind.containsKey(strategy.kind)) {
        throw ArgumentError.value(
          strategy.kind,
          'strategies',
          'two strategies for one kind',
        );
      }
      byKind[strategy.kind] = strategy;
    }
    return PanelPresentationController._(
      shell,
      policy ?? PanelPresentationPolicy.forFamily(PanelOsFamily.current),
      byKind,
      window,
      preferences?.dockPreferred ?? dockPreferred,
      preferences,
      dockWidths,
    );
  }

  PanelPresentationController._(
    this.shell,
    this.policy,
    this._strategies,
    PanelWindow window,
    bool dockPreferred,
    this._preferences,
    this._dockWidths,
  ) : _window = listen.ValueNotifier<PanelWindow>(window),
      _dockPreferred = listen.ValueNotifier<bool>(dockPreferred),
      _dockWanted = listen.ValueNotifier<double?>(_dockWidths?.width) {
    _shellEvents = shell.events.listen(_onShellEvent);
    _preferences?.changes.addListener(_onPreferencesChanged);
    _followOccupancyOf(_idleKind());
    _syncDock();
  }

  /// The wrapped shell: page and search state, the pages' controllers.
  final PanelShellController shell;

  /// The policy deciding kinds, triggers, dismissal, sizing and roles.
  final PanelPresentationPolicy policy;

  final Map<PanelPresentation, PanelPresentationStrategy> _strategies;
  final PreferenceStore? _preferences;
  final DockWidthStore? _dockWidths;
  final listen.ValueNotifier<PanelWindow> _window;
  final listen.ValueNotifier<bool> _dockPreferred;
  final listen.ValueNotifier<double?> _dockWanted;
  final _state = listen.ValueNotifier<PanelVisibility>(PanelVisibility.hidden);
  final _occupancy = listen.ValueNotifier<PanelOccupancy>(PanelOccupancy.zero);
  final _anchor = listen.ValueNotifier<Rect?>(null);
  final _guard = listen.ValueNotifier<bool>(false);
  final _interactions = _InteractionSignal();
  late final StreamSubscription<PanelEvent> _shellEvents;
  final _attachments = <_Attachment>[];
  var _holds = 0;
  var _disposed = false;
  // Whether the dock stood at the last sync: what a change of the answer is
  // measured against.
  var _dockStood = false;
  listen.ValueListenable<PanelOccupancy>? _followed;

  // --- State ----------------------------------------------------------------

  /// Whether and how the panel is on screen.
  listen.ValueListenable<PanelVisibility> get state => _state;

  /// The space the presentation takes, for the host to aggregate.
  ///
  /// The occupancy of the strategy of the active kind; while hidden, of the
  /// kind the policy would open now, so a keyboard strategy keeps publishing
  /// the soft keyboard's height and the host never adds it a second time.
  /// Zero for a kind without a strategy.
  listen.ValueListenable<PanelOccupancy> get occupancy => _occupancy;

  /// The host window the policy sizes against, as last reported.
  listen.ValueListenable<PanelWindow> get window => _window;

  /// Whether the user prefers the panel docked.
  listen.ValueListenable<bool> get dockPreferred => _dockPreferred;

  /// The width the user wants the dock to have, as dragged, or null before
  /// they dragged it. The width a dock has in the window is
  /// `policy.dockWidthIn(window.value, wanted: dockWanted.value)`.
  listen.ValueListenable<double?> get dockWanted => _dockWanted;

  /// The composer rectangle an anchored popup attaches to, in the
  /// coordinates of the box that hosts the view; null until reported.
  listen.ValueListenable<Rect?> get anchorRect => _anchor;

  /// The **auto-hide guard**: whether something keeps a self-dismissing
  /// popup open. True exactly while any [holdAutoHide] is unreleased.
  ///
  /// The search field's focus is not a hold. The reference client's panel
  /// hides on the pointer leaving whether or not search is focused, and a
  /// popup the pointer has not left stays open anyway.
  listen.ValueListenable<bool> get autoHideGuard => _guard;

  /// Signals whenever the user does something in the panel: a page change,
  /// search opening or closing, a pick, an action. For hosts that react to
  /// activity; no presentation times out on it.
  listen.Listenable get interactions => _interactions;

  /// Whether [dispose] has been called.
  bool get isDisposed => _disposed;

  /// The strategy drawing [kind], or null when none was registered.
  PanelPresentationStrategy? strategyFor(PanelPresentation kind) =>
      _strategies[kind];

  // --- Intents --------------------------------------------------------------

  /// Shows the panel.
  ///
  /// The kind is the host's [kind] when given and otherwise the policy's
  /// default for the current window and dock preference. Showing a panel that
  /// is already visible changes nothing unless [kind] names another kind, in
  /// which case the panel switches to it where it stands. Showing while the
  /// panel is hiding turns it back.
  void show({PanelPresentation? kind}) {
    if (_disposed) return;
    final target = policy.resolve(
      window: _window.value,
      dockPreferred: _dockPreferred.value,
      override: kind,
    );
    final current = _state.value;
    switch (current) {
      case PanelVisibility$Hidden():
        _commit(PanelVisibility.showing(target));
      case PanelVisibility$Showing() || PanelVisibility$Shown():
        if (kind != null && current.kind != target) {
          _commit(current.withKind(target));
        }
      case PanelVisibility$Hiding(kind: final active):
        _commit(
          PanelVisibility.showing(switch (kind) {
            null => active,
            _ => target,
          }),
        );
    }
  }

  /// Hides the panel; does nothing when it is hidden or already hiding.
  ///
  /// With [waitForIme] the strategy keeps the bottom space until the soft
  /// keyboard has taken it over (the user is about to type); other kinds
  /// ignore it.
  void hide({bool waitForIme = false}) {
    if (_disposed) return;
    final current = _state.value;
    if (current
        case PanelVisibility$Showing(:final kind) ||
            PanelVisibility$Shown(:final kind)) {
      _commit(PanelVisibility.hiding(kind, waitForIme: waitForIme));
    }
  }

  /// Hides a panel that is showing or shown, and shows one that is hidden or
  /// hiding. [kind] is passed to [show].
  void toggle({PanelPresentation? kind}) {
    if (_disposed) return;
    final current = _state.value;
    if (current case PanelVisibility$Showing() || PanelVisibility$Shown()) {
      hide();
    } else {
      show(kind: kind);
    }
  }

  /// Steps back by one level and returns whether it consumed the press.
  ///
  /// The order is fixed: the shell closes search first; then a visible panel
  /// hides, if its kind is dismissed by back (a dock is not). A panel that is
  /// already hiding still consumes the press, so a second back does not leave
  /// the screen mid-animation. A hidden panel consumes nothing.
  bool handleBack() {
    if (_disposed) return false;
    if (shell.handleBack()) return true;
    final current = _state.value;
    if (current.kind case final kind?
        when current.isVisible &&
            policy.dismissalsFor(kind).contains(PanelDismissal.back)) {
      hide();
      return true;
    }
    return false;
  }

  /// Reports the composer rectangle an anchored popup attaches to, in the
  /// coordinates of the box that hosts the view.
  void anchor(Rect composerRect) {
    if (_disposed) return;
    _anchor.value = composerRect;
  }

  /// Reports the host window. Its width decides whether a dock fits and how
  /// wide it is, its height how tall a popup is.
  ///
  /// A standing dock follows: a window that no longer has the room for it
  /// takes it away, one that has again brings it back (see the class
  /// documentation).
  void updateWindow(PanelWindow window) {
    if (_disposed) return;
    _window.value = window;
    _syncDock();
    _followOccupancyOf(_state.value.kind ?? _idleKind());
  }

  /// Follows a drag of the dock's resize strip: the dock is to be [wanted]
  /// logical pixels wide. Held to the policy's bounds in the window when it is
  /// used, not here, so the wish is what the user dragged to.
  ///
  /// Nothing is kept until [endDockResize]. A width that is not finite is
  /// ignored.
  void resizeDock(double wanted) {
    if (_disposed || !wanted.isFinite) return;
    _dockWanted.value = wanted;
  }

  /// Ends a drag of the dock: the wish is held to the policy's bounds and kept
  /// in the [DockWidthStore], if there is one.
  ///
  /// A failed write is reported to the zone by the store and never thrown
  /// into this call; the width stays in memory.
  void endDockResize() {
    if (_disposed) return;
    final wanted = _dockWanted.value;
    if (wanted == null) return;
    final held = wanted.clamp(policy.dockMinWidth, policy.dockMaxWidth);
    _dockWanted.value = held;
    unawaited(_dockWidths?.record(held) ?? Future<void>.value());
  }

  /// Records the user's choice to keep the panel docked and, when a popup is
  /// up in a window that can dock, moves it into the docked section.
  ///
  /// The choice is written to the preference store, if there is one.
  void dock() => _setDockPreferred(preferred: true);

  /// Records that the user no longer wants the panel docked; a docked section
  /// closes.
  ///
  /// The choice is written to the preference store, if there is one.
  void undock() => _setDockPreferred(preferred: false);

  /// Docks the panel when it is not preferred docked, and undocks it when it
  /// is: the action of a dock button.
  void toggleDock() {
    if (_dockPreferred.value) {
      undock();
    } else {
      dock();
    }
  }

  /// Keeps a self-dismissing presentation open until the returned hold is
  /// released: a menu or a variant picker is up, a drag is in progress, a
  /// pointer button pressed inside the panel is still down.
  ///
  /// This is the one seam for such claims. Holds are counted and independent:
  /// each [PanelAutoHideHold.release] undoes only its own hold, in any order,
  /// and the guard stays true until all are released. It notifies on the first
  /// hold and on the last release, not in between. A hold that outlives a
  /// hide stays in force for the next show. After [dispose] a hold is inert
  /// and releasing it is harmless.
  PanelAutoHideHold holdAutoHide() {
    final hold = _AutoHideHold(this);
    if (!_disposed) {
      _holds++;
      _updateGuard();
    }
    return hold;
  }

  // --- Views ----------------------------------------------------------------

  /// Registers a mounted view, which will play the motion of `showing` and
  /// `hiding` and settle it.
  ///
  /// While at least one is attached, [show] and [hide] enter the moving
  /// phases instead of landing at once.
  PanelPresentationAttachment attach() {
    final attachment = _Attachment(this);
    if (!_disposed) _attachments.add(attachment);
    return attachment;
  }

  // --- Lifecycle ------------------------------------------------------------

  /// Detaches from the shell and the strategies and drops every listener. The
  /// shell and the strategies are left to their owners. Idempotent.
  void dispose() {
    if (_disposed) return;
    final current = _state.value;
    _disposed = true;
    unawaited(_shellEvents.cancel());
    _preferences?.changes.removeListener(_onPreferencesChanged);
    _followed?.removeListener(_onStrategyOccupancy);
    _followed = null;
    if (current.isVisible) {
      shell.updatePresence(visible: false, opening: false);
    }
    _attachments.clear();
    _window.dispose();
    _dockPreferred.dispose();
    _dockWanted.dispose();
    _state.dispose();
    _occupancy.dispose();
    _anchor.dispose();
    _guard.dispose();
    _interactions.dispose();
  }

  // --- Internals ------------------------------------------------------------

  PanelPresentation _idleKind() => policy.resolve(
    window: _window.value,
    dockPreferred: _dockPreferred.value,
  );

  // Brings the dock to what the user and the window allow: on screen while
  // preferred and fitting, off it otherwise. Whatever else was showing in its
  // place (a popup) gives way to it.
  //
  // Acts when the answer changes, not on every call: a host reports its window
  // with every layout, and a dock that was hidden on purpose (`hide`) must not
  // come back with the next report of the same window.
  void _syncDock() {
    final stands = _dockPreferred.value && policy.canDock(_window.value);
    if (stands == _dockStood) return;
    _dockStood = stands;
    final current = _state.value;
    if (stands) {
      switch (current) {
        case PanelVisibility$Hidden() || PanelVisibility$Hiding():
          _commit(const PanelVisibility.showing(Docked()));
        case PanelVisibility$Showing(kind: Docked()) ||
            PanelVisibility$Shown(kind: Docked()):
          break;
        case PanelVisibility$Showing() || PanelVisibility$Shown():
          _commit(current.withKind(const Docked()));
      }
    } else if (current.kind case Docked() when current.isVisible) {
      hide();
    }
  }

  void _setDockPreferred({required bool preferred}) {
    if (_disposed) return;
    _applyDockPreferred(preferred: preferred);
    final store = _preferences;
    if (store != null) _persistDockPreferred(store, preferred: preferred);
  }

  // The state change of a new dock choice, wherever the choice came from.
  void _applyDockPreferred({required bool preferred}) {
    _dockPreferred.value = preferred;
    _syncDock();
    _followOccupancyOf(_state.value.kind ?? _idleKind());
  }

  Future<void> _persistDockPreferred(
    PreferenceStore store, {
    required bool preferred,
  }) async {
    try {
      await store.setDockPreferred(preferred: preferred);
    } on Object catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'panel_presentation',
          context: ErrorDescription('while persisting the dock preference'),
        ),
      );
    }
  }

  void _onPreferencesChanged() {
    final store = _preferences;
    if (_disposed || store == null) return;
    final preferred = store.dockPreferred;
    if (preferred != _dockPreferred.value) {
      _applyDockPreferred(preferred: preferred);
    }
  }

  void _commit(PanelVisibility next) {
    final settled = _attachments.isEmpty ? _settle(next) : next;
    if (settled == _state.value) return;
    _followOccupancyOf(settled.kind ?? _idleKind());
    shell.updatePresence(visible: settled.isVisible, opening: settled.isMoving);
    _state.value = settled;
  }

  PanelVisibility _settle(PanelVisibility state) => switch (state) {
    PanelVisibility$Showing(:final kind) => PanelVisibility.shown(kind),
    PanelVisibility$Hiding() => PanelVisibility.hidden,
    _ => state,
  };

  void _motionSettled(PanelVisibility settledFor) {
    if (_disposed || settledFor != _state.value) return;
    _commit(_settle(settledFor));
  }

  void _followOccupancyOf(PanelPresentation kind) {
    final next = _strategies[kind]?.occupancy;
    if (!identical(next, _followed)) {
      _followed?.removeListener(_onStrategyOccupancy);
      _followed = next;
      next?.addListener(_onStrategyOccupancy);
    }
    _occupancy.value = next?.value ?? PanelOccupancy.zero;
  }

  void _onStrategyOccupancy() {
    final followed = _followed;
    if (followed != null) _occupancy.value = followed.value;
  }

  void _onShellEvent(PanelEvent event) {
    _interactions.signal();
  }

  void _updateGuard() => _guard.value = _holds > 0;

  void _releaseHold() {
    if (_disposed) return;
    _holds--;
    _updateGuard();
  }

  void _detach(_Attachment attachment) {
    if (!_attachments.remove(attachment) || _disposed) return;
    if (_attachments.isEmpty) _commit(_settle(_state.value));
  }
}

/// A mounted view's registration with a controller.
abstract interface class PanelPresentationAttachment {
  /// Reports that the motion toward [settledFor] has finished.
  ///
  /// Moves `showing` to `shown` and `hiding` to `hidden`, provided the state
  /// is still [settledFor]; a report for a state that has been replaced is
  /// ignored.
  void motionSettled(PanelVisibility settledFor);

  /// Unregisters the view. When it was the last, a state that was moving
  /// settles at once. Idempotent.
  void detach();
}

/// A claim that keeps a self-dismissing presentation open.
abstract interface class PanelAutoHideHold {
  /// Releases the claim. Idempotent.
  void release();
}

final class _Attachment implements PanelPresentationAttachment {
  _Attachment(this._controller);

  final PanelPresentationController _controller;

  @override
  void motionSettled(PanelVisibility settledFor) =>
      _controller._motionSettled(settledFor);

  @override
  void detach() => _controller._detach(this);
}

final class _AutoHideHold implements PanelAutoHideHold {
  _AutoHideHold(this._controller);

  final PanelPresentationController _controller;
  var _released = false;

  @override
  void release() {
    if (_released) return;
    _released = true;
    _controller._releaseHold();
  }
}

/// The signal behind [PanelPresentationController.interactions]:
/// `notifyListeners` is protected, so the controller reaches it through this
/// subclass.
final class _InteractionSignal extends listen.ChangeNotifier {
  void signal() => notifyListeners();
}
