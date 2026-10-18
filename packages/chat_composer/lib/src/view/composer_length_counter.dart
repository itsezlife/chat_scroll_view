import 'dart:math' as math;

import 'package:chat_composer/src/input/composer_controller.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/widgets.dart';

/// The count of code points left in a message, drawn under the composer's row
/// once [visibleFrom] or fewer remain, and negative (in the destructive
/// colour) when the text is over `ComposerSpec.messageLengthLimit`.
///
/// It grows into the island and shrinks out of it, so the composer's extent
/// follows. [shake] is the refusal of a send: a damped sway across the
/// counter from 0 to 1.
class ComposerLengthCounter extends StatelessWidget {
  /// A counter of [controller]'s text against [limit].
  const ComposerLengthCounter({
    required this.controller,
    required this.limit,
    required this.shake,
    super.key,
  });

  /// How many code points may remain for the counter to show: the point
  /// where a user is close enough to want to know.
  static const int visibleFrom = 100;

  /// The text counted.
  final ComposerController controller;

  /// The budget, in code points.
  final int limit;

  /// Progress of the refusal shake, 0 at rest.
  final Animation<double> shake;

  static const double _fontSize = 12;
  static const double _endPad = 14;
  static const double _bottomPad = 4;
  static const double _shakeAmplitude = 6;
  static const double _shakeSways = 3;

  @override
  Widget build(BuildContext context) {
    final motion = ChromeMotionScope.of(
      context,
    ).specOf(MotionRole.listTransition);
    return AnimatedSize(
      duration: motion.duration,
      curve: motion.curve,
      alignment: Alignment.topCenter,
      child: ListenableBuilder(
        listenable: controller.text,
        builder: (context, _) {
          final remaining = limit - controller.length;
          if (remaining > visibleFrom) return const SizedBox.shrink();
          final over = remaining < 0;
          return Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Padding(
              padding: const EdgeInsetsDirectional.only(
                end: _endPad,
                bottom: _bottomPad,
              ),
              child: AnimatedBuilder(
                animation: shake,
                builder: (context, child) => Transform.translate(
                  offset: Offset(
                    _shakeAmplitude *
                        math.sin(shake.value * 2 * math.pi * _shakeSways) *
                        (1 - shake.value),
                    0,
                  ),
                  child: child,
                ),
                child: Text(
                  '$remaining',
                  style: TextStyle(
                    fontSize: _fontSize,
                    color: over
                        ? ChromeThemeScope.paletteOf(context).destructive
                        : ChromeThemeScope.placeholderOf(context).fieldHint,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
