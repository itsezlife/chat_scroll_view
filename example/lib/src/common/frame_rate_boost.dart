import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

/// Asks the platform for its top refresh rate while the app animates.
///
/// An idle Android display drops to a low rate (24 Hz on the reference
/// phone). A touch raises it at once; an animation no finger started — the
/// list scrolling to a new message, a panel opening from a key — ran its
/// first quarter second at that rate while the system worked out that frames
/// were coming. The app knows first: while tickers ask for frames it votes
/// the top rate on its surface, and once none has for [_linger] it withdraws
/// the vote, so an idle display still saves power. The watch is checked on a
/// timer, not timed per frame: an idle app draws no frame to time from.
abstract final class FrameRateBoost {
  static const _channel = MethodChannel('chat_scroll_view_example/frame_rate');

  /// How long after the last animated frame the vote stays: long enough to
  /// span the gap between two animations of one gesture.
  static const Duration _linger = Duration(milliseconds: 300);

  // A persistent frame callback cannot be removed: it is registered once and
  // [_enabled] switches the watch.
  static bool _registered = false;
  static bool _enabled = false;
  static Timer? _release;

  /// Whether a frame animated since [_release] was last armed.
  static bool _animated = false;

  /// Starts watching frames. Android only; idempotent.
  static void install() {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    _watch();
  }

  static void _watch() {
    _enabled = true;
    if (_registered) return;
    _registered = true;
    SchedulerBinding.instance.addPersistentFrameCallback(_onFrame);
  }

  static void _onFrame(Duration _) {
    // Tickers have asked for the next frame: something is animating.
    if (!_enabled || SchedulerBinding.instance.transientCallbackCount == 0) {
      return;
    }
    _animated = true;
    if (_release != null) return;
    unawaited(_send('high'));
    _arm();
  }

  static void _arm() {
    _animated = false;
    _release = Timer(_linger, _check);
  }

  /// Keeps the vote while frames still animate; withdraws it after a quiet
  /// [_linger].
  static void _check() {
    if (_animated) {
      _arm();
      return;
    }
    _release = null;
    unawaited(_send('default'));
  }

  static Future<void> _send(String method) async {
    try {
      await _channel.invokeMethod<void>(method);
    } on MissingPluginException {
      // No platform side (widget tests): nothing to vote on.
    }
  }

  /// Starts watching frames on any platform, for tests.
  @visibleForTesting
  static void debugInstall() => _watch();

  /// Stops watching and forgets the vote.
  @visibleForTesting
  static void debugReset() {
    _enabled = false;
    _release?.cancel();
    _release = null;
    _animated = false;
  }
}
