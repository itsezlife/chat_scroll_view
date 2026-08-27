import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:chat_chrome/src/motion/keyboard_panel_motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Leading search-field icon states.
enum EmojiSearchIconState {
  /// Magnifier.
  search,

  /// Chevron back (clears query).
  back,

  /// Indeterminate circular progress.
  progress,
}

/// Path-morphing search / progress / back icon.
///
/// Shared stroke path: magnifier lens + handle ↔ progress arc ↔ back chevron.
/// Leaving progress waits for the arc to hit the exit angle before the morph
/// continues (`waitingForProgressToEnd`). Duration 350ms, `easeOutQuint`.
class EmojiSearchStateIcon extends StatefulWidget {
  /// Creates the morphing icon.
  const EmojiSearchStateIcon({
    required this.state,
    required this.color,
    this.size = 24,
    super.key,
  });

  /// Target icon state.
  final EmojiSearchIconState state;

  /// Stroke color.
  final Color color;

  /// Paint bounds (Telegram intrinsic `dp(24)`).
  final double size;

  @override
  State<EmojiSearchStateIcon> createState() => _EmojiSearchStateIconState();
}

class _EmojiSearchStateIconState extends State<EmojiSearchStateIcon>
    with TickerProviderStateMixin {
  static const double _progressRadius = 0.25;
  static const double _strokeWidth = 1.333;

  late final AnimationController _morph;
  late final AnimationStatusListener _morphStatus;

  var _from = EmojiSearchIconState.search;
  var _to = EmojiSearchIconState.search;
  var _waitingForProgressToEnd = false;
  var _wereNotWaitingForProgressToEnd = false;
  var _progressStartedWithOverTo = false;
  var _progressAngleFrom = 0.0;
  var _progressAngleTo = 0.0;
  int? _progressStartMs;

  /// Latest arc angles (degrees) for the progress stroke.
  var _arcFrom = 0.0;
  var _arcSweep = 0.0;
  var _showArc = false;

  Ticker? _ticker;

  @override
  void initState() {
    super.initState();
    _morphStatus = (status) {
      if (status != AnimationStatus.completed) return;
      // Lock from=to so settled geometry doesn’t keep “fromProgress” extras.
      if (_from != _to) {
        _from = _to;
        _rebuild();
      }
      _stopTickerIfIdle();
    };
    _morph =
        AnimationController(
            vsync: this,
            duration: KeyboardPanelMotion.searchIconMorphDuration,
            value: 1,
          )
          ..addListener(_rebuild)
          ..addStatusListener(_morphStatus);
    _from = _to = widget.state;
    if (widget.state == EmojiSearchIconState.progress) {
      _ensureTicker();
    }
  }

  @override
  void didUpdateWidget(EmojiSearchStateIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      _setIconState(widget.state);
    }
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _morph
      ..removeListener(_rebuild)
      ..removeStatusListener(_morphStatus)
      ..dispose();
    super.dispose();
  }

  void _rebuild() {
    if (!mounted) return;
    _updateProgressArc(_progressValue(_easedMorph));
    setState(() {});
  }

  void _ensureTicker() {
    if (_ticker != null) return;
    _ticker = createTicker((_) => _rebuild())..start();
  }

  void _stopTickerIfIdle() {
    if (_waitingForProgressToEnd) return;
    if (_morph.isAnimating || _morph.value < 1) return;
    if (_to == EmojiSearchIconState.progress) return;
    if (_progressValue(_easedMorph) > 0.001) return;
    _ticker?.dispose();
    _ticker = null;
  }

  void _setIconState(EmojiSearchIconState state, {bool animated = true}) {
    if (_to == state) return;

    if (animated && _morph.value < 1) {
      _setIconState(_to, animated: false);
    }

    if (state == EmojiSearchIconState.progress) {
      _progressAngleFrom = 180;
      _progressStartMs = null;
      _showArc = false;
    } else if (_to == EmojiSearchIconState.progress) {
      _progressAngleTo = state == EmojiSearchIconState.search ? -45 : 0;
    }

    if (animated) {
      _from = _to;
      _to = state;
      _waitingForProgressToEnd =
          _from == EmojiSearchIconState.progress &&
          state != EmojiSearchIconState.progress;
      _morph.value = 0;
      if (!_waitingForProgressToEnd) {
        _morph.forward(from: 0);
      }
    } else {
      _from = _to = state;
      _waitingForProgressToEnd = false;
      _morph.value = 1;
    }
    _ensureTicker();
    _updateProgressArc(_progressValue(_easedMorph));
    setState(() {});
  }

  double get _easedMorph {
    final t = _waitingForProgressToEnd ? 0.0 : _morph.value;
    return Curves.easeOutQuint.transform(t.clamp(0.0, 1.0));
  }

  double _searchValue(double value) {
    if (_to == EmojiSearchIconState.search) {
      return _from == EmojiSearchIconState.search ? 1 : value;
    }
    return _from == EmojiSearchIconState.search ? 1 - value : 0;
  }

  double _backValue(double value) {
    if (_to == EmojiSearchIconState.back) {
      return _from == EmojiSearchIconState.back ? 1 : value;
    }
    return _from == EmojiSearchIconState.back ? 1 - value : 0;
  }

  double _progressValue(double value) {
    if (_to == EmojiSearchIconState.progress) {
      return _from == EmojiSearchIconState.progress ? 1 : value;
    }
    return _from == EmojiSearchIconState.progress ? 1 - value : 0;
  }

  /// Telegram `CircularProgressDrawable.getSegments`.
  static void _progressSegments(double t, List<double> segments) {
    segments[0] = math.max(0, 1520 * t / 5400 - 20);
    segments[1] = 1520 * t / 5400;
    for (var i = 0; i < 4; i++) {
      final t1 = ((t - i * 1350) / 667).clamp(0.0, 1.0);
      final t0 = ((t - (667 + i * 1350)) / 667).clamp(0.0, 1.0);
      segments[1] += Curves.fastOutSlowIn.transform(t1) * 250;
      segments[0] += Curves.fastOutSlowIn.transform(t0) * 250;
    }
  }

  static bool _containsAngle(double angle, double angleFrom, double angleTo) {
    var from = angleFrom % 360;
    if (from < 0) from += 360;
    var to = angleTo % 360;
    if (to < 0) to += 360;
    if (from > to) return angle >= from || angle <= to;
    return angle >= from && angle <= to;
  }

  void _updateProgressArc(double progressValue) {
    _showArc = false;
    if (progressValue <= 0) {
      _stopTickerIfIdle();
      return;
    }

    if (_progressStartMs == null && progressValue > 0.8) {
      _progressStartMs = DateTime.now().millisecondsSinceEpoch;
      _wereNotWaitingForProgressToEnd = _waitingForProgressToEnd;
    }
    final start = _progressStartMs;
    if (start == null) return;

    final elapsed = (DateTime.now().millisecondsSinceEpoch - start) % 5400;
    final segments = <double>[0, 0];
    _progressSegments(elapsed.toDouble(), segments);
    var fromAngle = segments[0];
    var toAngle = segments[1];
    if (_to != EmojiSearchIconState.progress && !_waitingForProgressToEnd) {
      final m =
          math.max(0, ((fromAngle - 180) / 360).floorToDouble()) * 360 + 180;
      toAngle = math.min(toAngle, m + _progressAngleTo);
      fromAngle = math.min(fromAngle, m + _progressAngleTo);
      fromAngle = lerpDouble(toAngle, fromAngle, progressValue)!;
    }

    final progressOverTo = _containsAngle(
      _progressAngleTo,
      _progressAngleFrom + fromAngle,
      _progressAngleFrom + toAngle,
    );
    if (_waitingForProgressToEnd && !_wereNotWaitingForProgressToEnd) {
      _wereNotWaitingForProgressToEnd = true;
      _progressStartedWithOverTo = progressOverTo;
    }
    if (_progressStartedWithOverTo && !progressOverTo) {
      _progressStartedWithOverTo = false;
    }
    if (_waitingForProgressToEnd &&
        progressOverTo &&
        !_progressStartedWithOverTo) {
      _waitingForProgressToEnd = false;
      if (_morph.value < 1 && !_morph.isAnimating) {
        _morph.forward();
      }
    }

    _arcFrom = _progressAngleFrom + fromAngle;
    _arcSweep = toAngle - fromAngle;
    _showArc = true;
    _ensureTicker();
  }

  @override
  Widget build(BuildContext context) {
    final value = _easedMorph;
    return CustomPaint(
      size: Size.square(widget.size),
      painter: _SearchStatePainter(
        color: widget.color,
        strokeWidth: _strokeWidth,
        searchValue: _searchValue(value),
        backValue: _backValue(value),
        progressValue: _progressValue(value),
        fromProgress: _from == EmojiSearchIconState.progress,
        progressRadius: _progressRadius,
        showArc: _showArc,
        arcFromDeg: _arcFrom,
        arcSweepDeg: _arcSweep,
      ),
    );
  }
}

class _SearchStatePainter extends CustomPainter {
  _SearchStatePainter({
    required this.color,
    required this.strokeWidth,
    required this.searchValue,
    required this.backValue,
    required this.progressValue,
    required this.fromProgress,
    required this.progressRadius,
    required this.showArc,
    required this.arcFromDeg,
    required this.arcSweepDeg,
  });

  final Color color;
  final double strokeWidth;
  final double searchValue;
  final double backValue;
  final double progressValue;
  final bool fromProgress;
  final double progressRadius;
  final bool showArc;
  final double arcFromDeg;
  final double arcSweepDeg;

  static double _lerp3(
    double a,
    double b,
    double c,
    double t1,
    double t2,
    double t3,
  ) => a * t1 + b * t2 + c * t3;

  @override
  void paint(Canvas canvas, Size size) {
    final mn = math.min(size.width, size.height);
    final cx = size.width / 2;
    final cy = size.height / 2;
    double x(double t) => cx - mn * (0.5 - t);
    double y(double t) => cy - mn * (0.5 - t);
    double w(double t) => mn * t;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    if (searchValue > 0) {
      final r = lerpDouble(0, w(0.208), searchValue)!;
      if (r >= w(0.075)) {
        canvas.drawCircle(
          Offset(
            lerpDouble(x(0.25), x(0.444), searchValue)!,
            lerpDouble(y(0.5), y(0.444), searchValue)!,
          ),
          r,
          paint,
        );
      }
    }

    if (searchValue > 0 || backValue > 0) {
      canvas.save();
      canvas
        ..translate(cx, cy)
        ..rotate(searchValue * 45 * math.pi / 180)
        ..translate(-cx, -cy);

      // Shaft + chevron in one drawPath so AA coverage unions at the tip
      // (separate drawLine + drawPath stacks and blobs during morph).
      final progressX = x(0.5 + progressRadius);
      final x1 = _lerp3(
        x(0.914),
        x(0.7638),
        fromProgress ? progressX : x(0.2409),
        searchValue,
        backValue,
        progressValue,
      );
      final x2 = _lerp3(
        x(0.658),
        x(0.2409),
        fromProgress ? progressX : x(0.2409),
        searchValue,
        backValue,
        progressValue,
      );
      final yMid = y(0.5);
      final path = Path();
      if ((x1 - x2).abs() > w(0.075)) {
        path
          ..moveTo(x1, yMid)
          ..lineTo(x2, yMid);
      }
      if (backValue > 0) {
        final ax = fromProgress
            ? lerpDouble(x(0.5 + progressRadius), x(0.2409), backValue)!
            : x(0.2409);
        // Telegram uses x(.2452); equals w(.2452) for a square icon.
        final arm = x(0.2452) * backValue;
        final top = Offset(ax + arm, lerpDouble(y(0.5), y(0.25), backValue)!);
        final tip = Offset(ax, yMid);
        final bot = Offset(ax + arm, lerpDouble(y(0.5), y(0.75), backValue)!);
        final armLen = math.max((top - tip).distance, (bot - tip).distance);
        if (armLen > w(0.075)) {
          path
            ..moveTo(top.dx, top.dy)
            ..lineTo(tip.dx, tip.dy)
            ..lineTo(bot.dx, bot.dy);
        }
      }
      canvas.drawPath(path, paint);
      canvas.restore();
    }

    if (showArc && progressValue > 0) {
      final rect = Rect.fromLTRB(
        x(0.5 - progressRadius),
        y(0.5 - progressRadius),
        x(0.5 + progressRadius),
        y(0.5 + progressRadius),
      );
      canvas.drawArc(
        rect,
        arcFromDeg * math.pi / 180,
        arcSweepDeg * math.pi / 180,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SearchStatePainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.searchValue != searchValue ||
      oldDelegate.backValue != backValue ||
      oldDelegate.progressValue != progressValue ||
      oldDelegate.fromProgress != fromProgress ||
      oldDelegate.showArc != showArc ||
      oldDelegate.arcFromDeg != arcFromDeg ||
      oldDelegate.arcSweepDeg != arcSweepDeg;
}
