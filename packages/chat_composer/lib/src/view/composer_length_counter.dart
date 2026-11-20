import 'dart:math' as math;

import 'package:chat_composer/src/input/composer_controller.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/widgets.dart';

/// The count of code points left in a message, standing over the composer's
/// primary button once [visibleFrom] or fewer remain, and negative (in the
/// destructive colour) when the text is over `ComposerSpec.messageLengthLimit`.
///
/// It is drawn over what is above the island and takes no room of the
/// composer's: the composer places it in a box [width] wide and [height] tall
/// whose bottom is the primary button's top, centred on the button. It
/// scales in from [hiddenScale] as it fades in, and out the same way
/// (`MotionRole.counterShow`); each change of the count rolls the digits that changed
/// ([ComposerRollingNumber]). [shake] is the refusal of a send: a damped sway
/// across the counter from 0 to 1.
class ComposerLengthCounter extends StatefulWidget {
  /// A counter of [controller]'s text against [limit].
  const ComposerLengthCounter({
    required this.controller,
    required this.limit,
    required this.shake,
    this.visibleFromLength,
    super.key,
  });

  /// How many code points may remain for the counter to show: the point
  /// where a user is close enough to want to know.
  static const int visibleFrom = 100;

  /// The counter's box: as wide as a composer button, and one line tall.
  static const double width = 44;

  /// The counter's box height.
  static const double height = 20;

  /// The scale the counter shows from and hides to.
  static const double hiddenScale = 0.5;

  /// The count's font size.
  static const double fontSize = 15;

  /// The text length from which the counter shows; null shows it when
  /// [visibleFrom] or fewer code points remain.
  final int? visibleFromLength;

  /// The text counted.
  final ComposerController controller;

  /// The budget, in code points.
  final int limit;

  /// Progress of the refusal shake, 0 at rest.
  final Animation<double> shake;

  @override
  State<ComposerLengthCounter> createState() => _ComposerLengthCounterState();
}

class _ComposerLengthCounterState extends State<ComposerLengthCounter>
    with SingleTickerProviderStateMixin {
  late final AnimationController _$shown = AnimationController(vsync: this);
  // The count last shown: it stays on screen while the counter hides.
  int _count = 0;

  static const double _shakeAmplitude = 3.5;
  static const double _shakeSways = 3;

  @override
  void initState() {
    super.initState();
    widget.controller.text.addListener(_changed);
    _changed(animate: false);
  }

  @override
  void didUpdateWidget(ComposerLengthCounter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.text.removeListener(_changed);
      widget.controller.text.addListener(_changed);
    }
    _changed();
  }

  @override
  void dispose() {
    widget.controller.text.removeListener(_changed);
    _$shown.dispose();
    super.dispose();
  }

  bool get _visible {
    final from = widget.visibleFromLength;
    final remaining = widget.limit - widget.controller.length;
    return from == null
        ? remaining <= ComposerLengthCounter.visibleFrom
        : widget.controller.length >= from;
  }

  void _changed({bool animate = true}) {
    final visible = _visible;
    final remaining = widget.limit - widget.controller.length;
    if (visible && remaining != _count) {
      if (mounted) {
        setState(() => _count = remaining);
      } else {
        _count = remaining;
      }
    }
    final target = visible ? 1.0 : 0.0;
    if (!animate || !mounted) {
      _$shown.value = target;
    } else if (_$shown.value != target) {
      final spec = ChromeMotionScope.of(context).specOf(MotionRole.counterShow);
      _$shown.animateTo(target, duration: spec.duration, curve: spec.curve);
    }
  }

  @override
  Widget build(BuildContext context) {
    final over = _count < 0;
    final color = over
        ? ChromeThemeScope.paletteOf(context).destructive
        : ChromeThemeScope.placeholderOf(context).fieldHint;
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: Listenable.merge([_$shown, widget.shake]),
        builder: (context, child) {
          final shown = _$shown.value;
          if (shown == 0) return const SizedBox.shrink();
          final shake = widget.shake.value;
          final scale =
              ComposerLengthCounter.hiddenScale +
              (1 - ComposerLengthCounter.hiddenScale) * shown;
          return Opacity(
            opacity: shown,
            child: Transform.translate(
              offset: Offset(
                _shakeAmplitude *
                    math.sin(shake * 2 * math.pi * _shakeSways) *
                    (1 - shake),
                0,
              ),
              child: Transform.scale(scale: scale, child: child),
            ),
          );
        },
        // Centred on the box, and drawn past it when it is wider (a long
        // negative count), as nothing is under it to make room.
        child: OverflowBox(
          maxWidth: double.infinity,
          child: ComposerRollingNumber(
            key: const ValueKey('composer-length-counter'),
            value: _count,
            style: TextStyle(
              fontSize: ComposerLengthCounter.fontSize,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}

/// A number whose changed digits roll: on each change the digits that
/// differ from the ones before slide out and the new ones in
/// (`MotionRole.digitRoll`). A number that grows brings its new digits down from above;
/// one that shrinks brings them up from below. When the number's width
/// changes every digit rolls, so the centred number never jumps.
class ComposerRollingNumber extends StatefulWidget {
  /// [value] in [style].
  const ComposerRollingNumber({
    required this.value,
    required this.style,
    super.key,
  });

  /// The number shown.
  final int value;

  /// Its text style.
  final TextStyle style;

  @override
  State<ComposerRollingNumber> createState() => _ComposerRollingNumberState();
}

class _ComposerRollingNumberState extends State<ComposerRollingNumber>
    with SingleTickerProviderStateMixin {
  late final AnimationController _$roll = AnimationController(vsync: this);
  Curve _curve = Curves.linear;
  String _old = '';
  // Each index: whether the digit there rolls.
  List<bool> _rolls = const [];
  // 1: rolling up (the number shrank), -1: rolling down (it grew).
  double _direction = 1;

  @override
  void didUpdateWidget(ComposerRollingNumber oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value == widget.value) return;
    final old = '${oldWidget.value}';
    final now = '${widget.value}';
    _old = old;
    _direction = widget.value > oldWidget.value ? -1 : 1;
    final replace = _width(old) != _width(now);
    _rolls = [
      for (var i = 0; i < now.length; i++)
        replace || i >= old.length || old[i] != now[i],
    ];
    final spec = ChromeMotionScope.of(context).specOf(MotionRole.digitRoll);
    _curve = spec.curve;
    _$roll
      ..duration = spec.duration
      ..forward(from: 0);
  }

  double _width(String text) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: widget.style),
      textDirection: TextDirection.ltr,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  @override
  void dispose() {
    _$roll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = '${widget.value}';
    return AnimatedBuilder(
      animation: _$roll,
      builder: (context, _) {
        final t = _curve.transform(_$roll.value);
        final rolling = _$roll.isAnimating;
        // From the direction (1 or -1) at the start to 0 at the end.
        final progress = rolling ? _direction * (1 - t) : 0.0;
        return Row(
          mainAxisSize: MainAxisSize.min,
          textDirection: TextDirection.ltr,
          children: [
            for (var i = 0; i < now.length; i++)
              _digit(
                now[i],
                old: rolling && i < _rolls.length && _rolls[i]
                    ? (i < _old.length ? _old[i] : '')
                    : null,
                progress: rolling && i < _rolls.length && _rolls[i]
                    ? progress
                    : 0,
              ),
            // Digits the old number had past the new one's end roll out.
            if (rolling)
              for (var i = now.length; i < _old.length; i++)
                _digit('', old: _old[i], progress: progress),
          ],
        );
      },
    );
  }

  Widget _digit(
    String digit, {
    required String? old,
    required double progress,
  }) {
    final text = Text(digit, style: widget.style);
    if (old == null || progress == 0) return text;
    final out = progress.abs();
    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (old.isNotEmpty)
          Positioned(
            left: 0,
            top: 0,
            child: Opacity(
              opacity: out,
              child: FractionalTranslation(
                // Out the way the new digit comes from the other side.
                translation: Offset(
                  0,
                  progress > 0 ? progress - 1 : 1 + progress,
                ),
                child: Text(old, style: widget.style),
              ),
            ),
          ),
        Opacity(
          opacity: 1 - out,
          child: FractionalTranslation(
            translation: Offset(0, progress),
            child: text,
          ),
        ),
      ],
    );
  }
}
