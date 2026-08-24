import 'package:flutter/animation.dart';
import 'package:flutter/scheduler.dart';
import 'package:panel_catalog/src/model/catalog_leaf.dart';
import 'package:panel_catalog/src/viewport/overshoot_curve.dart';

/// Press progress for one catalog leaf under pointer-down.
///
/// Owns the press [AnimationController] and which [CatalogLeaf] is pressed.
/// Does **not** own hit-testing or gesture arena resolution — the render
/// object calls [pressIn] / [pressOut] from pointer + recognizer edges.
///
/// ## Scale contract
///
/// Paint multiplies glyph/placeholder draw by:
///
/// ```text
/// scale = 0.8 + 0.2 * (1 − progress)
/// ```
///
/// where [progress] is `0` idle … `1` fully pressed. Release may drive
/// [progress] slightly **negative** (overshoot) so scale briefly exceeds `1`.
/// Idle mounts skip ticker allocation until the first [pressIn].
///
/// ## Lifecycle
///
/// Create with a [TickerProvider] owned by the attached render object.
/// Call [dispose] on detach/dispose — safe if never pressed.
final class CatalogLeafPress {
  /// Creates idle press state. Tickers come from [vsync].
  CatalogLeafPress({required TickerProvider vsync, required this.onChanged})
    : _vsync = vsync;

  final TickerProvider _vsync;

  /// Fired when [progress] or [pressedLeaf] changes (drive [markNeedsPaint]).
  final VoidCallback onChanged;

  /// Release settle duration for press-out overshoot.
  static const Duration releaseDuration = Duration(milliseconds: 350);

  /// [OvershootCurve] tension for [releaseDuration].
  static const double releaseTension = 5;

  AnimationController? _controller;
  CatalogLeaf? _pressedLeaf;
  var _pointerDown = false;

  /// Leaf currently receiving press feedback, or `null` when idle / settled.
  CatalogLeaf? get pressedLeaf => _pressedLeaf;

  /// Press amount: `0` idle, `1` fully pressed; may be slightly negative on
  /// overshoot release. `0` when never pressed.
  double get progress => _controller?.value ?? 0;

  /// Paint scale for the pressed leaf (`1` when no active press animation).
  double get scale {
    if (_pressedLeaf == null && progress == 0) return 1;
    return 0.8 + 0.2 * (1 - progress);
  }

  AnimationController get _ensureController {
    return _controller ??= AnimationController(
      vsync: _vsync,
      value: 0,
      lowerBound: -0.35,
      upperBound: 1,
    )..addListener(onChanged);
  }

  double get _pressStep {
    final hz = SchedulerBinding
        .instance
        .platformDispatcher
        .views
        .first
        .display
        .refreshRate
        .clamp(30.0, 120.0);
    return (1000.0 / hz).clamp(0.0, 40.0) / 100.0;
  }

  Duration _pressInDuration(AnimationController pressed) {
    final hz = SchedulerBinding
        .instance
        .platformDispatcher
        .views
        .first
        .display
        .refreshRate
        .clamp(30.0, 120.0);
    final remaining = (1 - pressed.value).clamp(0.0, 1.0);
    final step = _pressStep;
    final frames = step <= 0 ? 6.0 : remaining / step;
    return Duration(
      milliseconds: (frames * (1000 / hz)).round().clamp(16, 200),
    );
  }

  /// Starts press-in for [leaf].
  ///
  /// Idempotent while the pointer is already down for this press session.
  /// Call [pressOut] before a new [pressIn] for another leaf.
  void pressIn(CatalogLeaf leaf) {
    if (_pointerDown) return;
    _pointerDown = true;
    _pressedLeaf = leaf;
    final pressed = _ensureController;
    pressed.stop();
    // One paint step immediately so UP before the first ticker tick still
    // has progress to spring from.
    pressed.value = (pressed.value + _pressStep).clamp(0.0, 1.0);
    pressed.animateTo(
      1,
      duration: _pressInDuration(pressed),
      curve: Curves.linear,
    );
    onChanged();
  }

  /// Releases press with overshoot settle.
  ///
  /// Keeps [pressedLeaf] until settle reaches idle so paint can overshoot on
  /// the correct cell. No-op when not pointer-down.
  void pressOut() {
    if (!_pointerDown) return;
    _pointerDown = false;
    final pressed = _controller;
    if (pressed == null) return;
    if (pressed.value == 0 && !pressed.isAnimating) {
      _pressedLeaf = null;
      onChanged();
      return;
    }
    // Guarantees release spring even when DOWN→UP was shorter than one frame.
    if (pressed.value < _pressStep) {
      pressed.value = _pressStep;
    }
    pressed.stop();
    pressed
        .animateTo(
          0,
          duration: releaseDuration,
          curve: const OvershootCurve(releaseTension),
        )
        .whenComplete(() {
          if (!_pointerDown && pressed.value == 0) {
            _pressedLeaf = null;
            onChanged();
          }
        });
    onChanged();
  }

  /// Drops the controller. Idempotent.
  void dispose() {
    _controller?.removeListener(onChanged);
    _controller?.dispose();
    _controller = null;
    _pressedLeaf = null;
    _pointerDown = false;
  }
}

/// Minimal [TickerProvider] for a render object that owns press animation.
///
/// Tickers are disposed with [dispose]. Does not participate in [TickerMode]
/// muting — callers SHOULD dispose on detach so background surfaces stop.
final class CatalogPressTickerProvider implements TickerProvider {
  final List<Ticker> _tickers = <Ticker>[];

  @override
  Ticker createTicker(TickerCallback onTick) {
    final ticker = Ticker(onTick, debugLabel: 'catalog-leaf-press');
    _tickers.add(ticker);
    return ticker;
  }

  /// Disposes every ticker created via [createTicker]. Idempotent.
  void dispose() {
    for (final ticker in _tickers) {
      ticker.dispose();
    }
    _tickers.clear();
  }
}
