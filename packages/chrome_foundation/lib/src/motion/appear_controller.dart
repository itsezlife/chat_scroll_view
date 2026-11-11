import 'dart:async';

import 'package:chrome_foundation/src/motion/appear_motion.dart';
import 'package:flutter/widgets.dart';

/// The clocks of one surface's appear motion: a show clock and a hide clock,
/// so an interrupted show or hide turns back from where the surface is.
///
/// The surface is drawn at [frameOf] its motion: the show's frame at the
/// show clock under the hide's frame at the hide clock
/// ([AppearFrame.compose]). The two run apart:
///
/// - [hide] fades the surface out (the hide clock from where it is to its
///   end, over the whole hide) while a show still under way goes on beneath
///   it, so a surface that was growing keeps growing as it goes.
/// - [show] during a hide turns the hide clock back from where it is to its
///   start, over the whole hide; the show clock, done or under way, goes on.
///   After a hide that ran to its end, the show starts over.
///
/// A `ChromeAppear` plays one; a surface whose clock is owned elsewhere (a
/// presentation that reports when its motion settles) holds one itself and
/// draws [frameOf] with an `AppearFrameView`.
final class AppearController implements Listenable {
  /// Clocks ticking on [vsync]; the surface starts hidden, or shown when
  /// [shown].
  AppearController({required TickerProvider vsync, bool shown = false})
    : _show = AnimationController(vsync: vsync, value: shown ? 1 : 0),
      _hide = AnimationController(vsync: vsync);

  final AnimationController _show;
  final AnimationController _hide;
  late final Listenable _both = Listenable.merge([_show, _hide]);
  Completer<void>? _pending;

  /// How far the show has come, 0 to 1.
  double get showProgress => _show.value;

  /// How far the hide has come, 0 to 1.
  double get hideProgress => _hide.value;

  /// Whether the last request was a hide.
  bool get isHiding => _hiding;
  var _hiding = false;

  /// The surface's frame under [motion] now.
  AppearFrame frameOf(AppearMotion motion) => AppearFrame.compose(
    show: motion.showAt(_show.value),
    hide: motion.hideAt(_hide.value),
  );

  /// Brings the surface up: the show over [showDuration], a hide under way
  /// turned back over [hideDuration]. Completes when the surface is up, or
  /// when a newer request replaces this one.
  Future<void> show({
    required Duration showDuration,
    required Duration hideDuration,
  }) {
    _hiding = false;
    final done = _replace();
    if (_hide.value >= 1) {
      // Gone: it comes up again from the start.
      _hide.value = 0;
      _show.value = 0;
    }
    final clocks = <Future<void>>[];
    if (_show.value < 1) {
      _show.duration = showDuration;
      clocks.add(_show.forward().orCancel);
    }
    if (_hide.value > 0) {
      clocks.add(_hide.animateBack(0, duration: hideDuration).orCancel);
    }
    unawaited(_settle(done, clocks));
    return done.future;
  }

  /// Takes the surface away over [hideDuration], from where it is. Completes
  /// when it is gone, or when a newer request replaces this one.
  Future<void> hide({required Duration hideDuration}) {
    _hiding = true;
    final done = _replace();
    unawaited(
      _settle(done, [
        if (_hide.value < 1)
          _hide.animateTo(1, duration: hideDuration).orCancel,
      ]),
    );
    return done.future;
  }

  Completer<void> _replace() {
    final previous = _pending;
    if (previous != null && !previous.isCompleted) previous.complete();
    return _pending = Completer<void>();
  }

  // Completes [done] once [clocks] end. A clock stopped early (a newer
  // request turned it, or the controller was disposed) fails with
  // [TickerCanceled]; whoever stopped it completed [done] already. Any other
  // error is not this controller's to hide and is left to the zone.
  Future<void> _settle(Completer<void> done, List<Future<void>> clocks) async {
    try {
      await Future.wait(clocks);
    } on TickerCanceled {
      // Stopped by a newer request or by dispose.
    }
    if (!done.isCompleted) done.complete();
  }

  /// Stops both clocks.
  void dispose() {
    final pending = _pending;
    if (pending != null && !pending.isCompleted) pending.complete();
    _show.dispose();
    _hide.dispose();
  }

  @override
  void addListener(VoidCallback listener) => _both.addListener(listener);

  @override
  void removeListener(VoidCallback listener) => _both.removeListener(listener);
}
