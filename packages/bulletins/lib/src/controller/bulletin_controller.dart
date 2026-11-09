import 'dart:async';

import 'package:bulletins/src/bulletin/bulletin.dart';
import 'package:bulletins/src/controller/bulletin_clock.dart';
import 'package:bulletins/src/policy/bulletin_policy.dart';
import 'package:flutter/foundation.dart';

/// Why a bulletin closed. Every bulletin closes exactly once.
enum BulletinExit {
  /// Its timeout ran out.
  timedOut,

  /// Another bulletin was shown on the same controller.
  replaced,

  /// The host dismissed it (`BulletinHandle.dismiss`,
  /// `BulletinController.dismiss`).
  dismissed,

  /// The user threw it away with a swipe.
  swiped,

  /// The user pressed its button action.
  actionPressed,

  /// The user pressed Undo. The only exit after which an undo bulletin does
  /// not commit.
  undone,

  /// Its surface went: the host view unmounted, or the controller was
  /// disposed.
  surfaceGone;

  /// Whether an undo bulletin closing this way commits.
  bool get commits => this != undone;
}

/// The **bulletin controller**: the one slot of a surface.
///
/// The host creates one per surface (a screen, a sheet, a window), mounts it
/// with a `BulletinHost` and disposes it with the surface. [show] puts a
/// bulletin in the slot and closes the one there as
/// [BulletinExit.replaced]; there is no queue.
///
/// ## Closing and commit on leave
///
/// Every [BulletinHandle] closes exactly once, with a [BulletinExit], and
/// [BulletinHandle.closed] completes with it. An undo bulletin's
/// [BulletinAction$Undo.onCommit] runs once when it closes by any exit but
/// [BulletinExit.undone]: a timeout, a replacement, a dismissal, a swipe, the
/// host view going ([detach]) or [dispose]. A host that applied a change
/// behind an Undo wires its undo and commit here and can rely on exactly one
/// of them running.
///
/// ## Timer
///
/// A bulletin's timeout, from [policy], starts when the view reports it has
/// entered ([BulletinHandle.markEntered]), so the time on screen is the
/// whole timeout. Time is read from the [BulletinClock].
///
/// A callback of the bulletin (undo, commit, a button) that throws is
/// reported to `FlutterError.reportError`; the bulletin closes regardless.
final class BulletinController {
  /// A controller timing bulletins by [policy] (the running platform's family
  /// by default) on [clock].
  BulletinController({BulletinPolicy? policy, BulletinClock? clock})
    : policy = policy ?? BulletinPolicy.current(),
      _clock = clock ?? BulletinClock.system;

  /// The layout, motion and timing values of this surface; fixed for the
  /// controller's life.
  final BulletinPolicy policy;

  final BulletinClock _clock;
  final ValueNotifier<BulletinHandle?> _$current = ValueNotifier(null);
  bool _$isDisposed = false;

  /// The bulletin in the slot, or null. Notifies when a bulletin is shown and
  /// when the one in the slot closes.
  ValueListenable<BulletinHandle?> get current => _$current;

  /// Whether [dispose] has run.
  bool get isDisposed => _$isDisposed;

  /// Shows [bulletin], closing the one in the slot as replaced.
  ///
  /// On a disposed controller the bulletin never shows: its handle closes at
  /// once as [BulletinExit.surfaceGone], which commits an undo bulletin.
  BulletinHandle show(Bulletin bulletin) {
    final timeout = policy.timeoutFor(bulletin.effectiveDuration);
    assert(
      timeout == null || timeout > Duration.zero,
      'a bulletin timeout must be positive, was $timeout',
    );
    final handle = BulletinHandle._(this, bulletin, timeout);
    if (_$isDisposed) {
      handle._close(BulletinExit.surfaceGone);
      return handle;
    }
    _$current.value?._close(BulletinExit.replaced, notify: false);
    _$current.value = handle;
    return handle;
  }

  /// Closes the bulletin in the slot, if any, as dismissed.
  void dismiss() => _$current.value?.dismiss();

  /// Closes the bulletin in the slot as [BulletinExit.surfaceGone]: the host
  /// view calls it when it unmounts. The controller stays usable for a view
  /// mounted later.
  void detach() => _$current.value?._close(BulletinExit.surfaceGone);

  /// Closes the bulletin in the slot as [BulletinExit.surfaceGone] and
  /// releases the listeners. Idempotent; a later [show] closes at once.
  void dispose() {
    if (_$isDisposed) return;
    detach();
    _$isDisposed = true;
    _$current.dispose();
  }

  // A replaced handle closes with notify false: [show] puts the new handle
  // in the slot next, and that one notification covers both changes.
  void _closed(BulletinHandle handle, {required bool notify}) {
    if (!notify || _$isDisposed) return;
    if (identical(_$current.value, handle)) _$current.value = null;
  }
}

/// One bulletin shown through a [BulletinController]: its state and the
/// commands of the view and the host.
///
/// Created by [BulletinController.show]; every command on a closed handle
/// does nothing.
final class BulletinHandle {
  BulletinHandle._(this._controller, this.bulletin, this.timeout);

  final BulletinController _controller;

  /// What is shown.
  final Bulletin bulletin;

  /// How long the bulletin stays once entered, from the controller's policy;
  /// null when it stays until dismissed.
  final Duration? timeout;

  final Completer<BulletinExit> _$closed = Completer<BulletinExit>();
  BulletinExit? _$exit;
  bool _$isEntered = false;
  bool _$isPaused = false;
  BulletinTimer? _$timer;
  Duration? _$deadline;

  /// Completes with the exit when the bulletin closes; never with an error.
  Future<BulletinExit> get closed => _$closed.future;

  /// How the bulletin closed, or null while it is open.
  BulletinExit? get exit => _$exit;

  /// Whether the bulletin has closed.
  bool get isClosed => _$exit != null;

  /// Whether the view has reported the bulletin entered.
  bool get isEntered => _$isEntered;

  /// Whether the timer is held by [pause].
  bool get isPaused => _$isPaused;

  /// The time left before the bulletin times out: counting down while the
  /// timer runs, the whole [timeout] before it enters or while paused, zero
  /// once closed, and null without a timeout.
  Duration? get remaining {
    final timeout = this.timeout;
    if (timeout == null) return null;
    if (isClosed) return Duration.zero;
    return switch (_$deadline) {
      final deadline? => _max(deadline - _controller._clock.now),
      null => timeout,
    };
  }

  static Duration _max(Duration left) =>
      left < Duration.zero ? Duration.zero : left;

  // --- View-facing ---

  /// Reports that the enter transition finished: the timer starts unless
  /// paused. Later calls do nothing.
  void markEntered() {
    if (isClosed || _$isEntered) return;
    _$isEntered = true;
    _startTimer();
  }

  /// Holds the timer, for instance while the bulletin is pressed.
  void pause() {
    if (isClosed || _$isPaused) return;
    _$isPaused = true;
    _cancelTimer();
  }

  /// Releases [pause]: the whole timeout starts again once entered.
  void resume() {
    if (isClosed || !_$isPaused) return;
    _$isPaused = false;
    _startTimer();
  }

  /// Closes the bulletin as thrown away by a swipe.
  void swipeAway() => _close(BulletinExit.swiped);

  /// Presses the bulletin's action: Undo runs its undo and closes as undone,
  /// a button runs its callback and closes as pressed. Does nothing without
  /// an action.
  void pressAction() {
    if (isClosed) return;
    switch (bulletin.action) {
      case BulletinAction$Undo(:final onUndo):
        _close(BulletinExit.undone);
        _guard(onUndo, 'running an undo');
      case BulletinAction$Button(:final onPressed):
        _close(BulletinExit.actionPressed);
        _guard(onPressed, 'running a bulletin action');
      case null:
        break;
    }
  }

  // --- Host-facing ---

  /// Closes the bulletin as dismissed by the host.
  void dismiss() => _close(BulletinExit.dismissed);

  // --- Machinery ---

  void _startTimer() {
    final timeout = this.timeout;
    if (timeout == null || !_$isEntered || _$isPaused) return;
    _$deadline = _controller._clock.now + timeout;
    _$timer = _controller._clock.after(
      timeout,
      () => _close(BulletinExit.timedOut),
    );
  }

  void _cancelTimer() {
    _$timer?.cancel();
    _$timer = null;
    _$deadline = null;
  }

  void _close(BulletinExit exit, {bool notify = true}) {
    if (isClosed) return;
    _$exit = exit;
    _cancelTimer();
    _controller._closed(this, notify: notify);
    if (bulletin.action case BulletinAction$Undo(
      :final onCommit?,
    ) when exit.commits) {
      _guard(onCommit, 'committing an undo');
    }
    _$closed.complete(exit);
  }

  void _guard(VoidCallback callback, String context) {
    try {
      callback();
    } on Object catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'bulletins',
          context: ErrorDescription('while $context'),
        ),
      );
    }
  }
}
