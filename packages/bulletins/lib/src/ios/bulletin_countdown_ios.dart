import 'dart:async';
import 'dart:math' as math;

import 'package:bulletins/src/controller/bulletin_controller.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// The iOS undo countdown: a ring that empties over a bulletin's time left,
/// with the seconds left inside it. Draws nothing for a bulletin without a
/// timeout.
///
/// The digits tick every 0.5 s and show the whole part of what is left, not
/// the clock's exact seconds, so a 5 s bulletin shows 5 for its first half
/// second, then 4, and 0 in its last half second. A change slides the new
/// digit down from 10 above while it fades in, and the old one down 10 while
/// it fades out, in 0.12 s. The digits are 16 regular; the ring is 30 across.
///
/// The ring's stroke and direction: a 2-wide round-capped arc that starts at
/// the top and empties counter-clockwise, as the stock countdown draws it.
class BulletinCountdownIOS extends StatefulWidget {
  /// A countdown of [handle] in [color], [size] square.
  const BulletinCountdownIOS({
    required this.handle,
    required this.color,
    this.size = 30,
    super.key,
  });

  /// The bulletin counted down.
  final BulletinHandle handle;

  /// The ring and digit colour.
  final Color color;

  /// The ring's diameter.
  final double size;

  /// The digits' text size.
  static const double digitSize = 16;

  /// How far a digit slides when it changes.
  static const double digitShift = 10;

  /// How long a digit change takes.
  static const Duration digitChange = Duration(milliseconds: 120);

  /// The digit shown when [remaining] of [timeout] is left.
  static int digitOf(Duration timeout, Duration remaining) {
    const tick = 500;
    final ticks = (timeout - remaining).inMilliseconds ~/ tick;
    final left = timeout.inMilliseconds - ticks * tick;
    return math.max(0, left) ~/ 1000;
  }

  @override
  State<BulletinCountdownIOS> createState() => _BulletinCountdownIOSState();
}

class _BulletinCountdownIOSState extends State<BulletinCountdownIOS>
    with TickerProviderStateMixin {
  // The ring empties continuously, so it repaints every frame while mounted.
  late final Ticker _$frames;
  late final AnimationController _$change = AnimationController(
    vsync: this,
    duration: BulletinCountdownIOS.digitChange,
    value: 1,
  );
  int? _$digit;
  int? _$previous;

  @override
  void initState() {
    super.initState();
    _$digit = _currentDigit();
    _$frames = createTicker((_) => _onFrame());
    unawaited(_$frames.start());
  }

  @override
  void dispose() {
    _$frames.dispose();
    _$change.dispose();
    super.dispose();
  }

  int? _currentDigit() {
    final handle = widget.handle;
    return switch ((handle.timeout, handle.remaining)) {
      (final timeout?, final remaining?) => BulletinCountdownIOS.digitOf(
        timeout,
        remaining,
      ),
      _ => null,
    };
  }

  void _onFrame() {
    final digit = _currentDigit();
    if (digit != _$digit) {
      _$previous = _$digit;
      _$digit = digit;
      unawaited(_$change.forward(from: 0));
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final handle = widget.handle;
    final (timeout, remaining) = (handle.timeout, handle.remaining);
    if (timeout == null || remaining == null) return const SizedBox.shrink();
    final fraction = remaining.inMicroseconds / timeout.inMicroseconds;
    final t = Curves.easeInOut.transform(_$change.value);
    final changing = _$change.isAnimating;
    return SizedBox.square(
      dimension: widget.size,
      child: CustomPaint(
        painter: _RingPainter(fraction: fraction, color: widget.color),
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (_$previous case final previous? when changing)
              _digit(previous, shift: t, opacity: 1 - t),
            if (_$digit case final digit?)
              _digit(digit, shift: t - 1, opacity: changing ? t : 1),
          ],
        ),
      ),
    );
  }

  Widget _digit(int digit, {required double shift, required double opacity}) =>
      Opacity(
        opacity: opacity,
        child: Transform.translate(
          offset: Offset(0, shift * BulletinCountdownIOS.digitShift),
          child: Text(
            '$digit',
            style: TextStyle(
              color: widget.color,
              fontSize: BulletinCountdownIOS.digitSize,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
      );
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.fraction, required this.color});

  final double fraction;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 2.0;
    final rect = (Offset.zero & size).deflate(stroke / 2);
    canvas.drawArc(
      rect,
      -math.pi / 2,
      -2 * math.pi * fraction.clamp(0, 1),
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.fraction != fraction || old.color != color;
}
