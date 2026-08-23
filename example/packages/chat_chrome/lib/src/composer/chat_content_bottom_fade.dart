import 'package:flutter/material.dart';

/// Soft bottom content fade under the composer / keyboard chrome.
///
/// Ports the color fast-path of Telegram's bottom
/// `BlurredBackgroundWithFadeDrawable` (`opacity: true`): a [fadeHeight]
/// ramp at the **top** of [zoneHeight], then a clamped semi-opaque wash to
/// the bottom edge. Drawn over the message list and under the input island.
///
/// **Stops** (top → bottom, base alpha [A]): `0`, `0x60·A/285`,
/// `0xB0·A/285`, `0xE8·A/285`. Default ramp is 48 logical pixels.
class ChatContentBottomFade extends StatelessWidget {
  /// Creates a bottom content fade of [zoneHeight] using [color].
  const ChatContentBottomFade({
    required this.zoneHeight,
    required this.color,
    this.fadeHeight = defaultFadeHeight,
    super.key,
  });

  /// Soft-edge ramp (`setFadeHeightBottom(dp(48))`).
  static const double defaultFadeHeight = 48;

  /// Full fade zone from the physical bottom (inset + island + gaps).
  final double zoneHeight;

  /// Fill color ([ChatChromeColors.contentBottomFade] — not panel fill).
  final Color color;

  /// Height of the transparent→wash ramp at the top of the zone.
  final double fadeHeight;

  /// Alpha stops for the opacity gradient (`createGradient(…, opacity=true)`).
  static List<Color> opacityStops(Color color) {
    final a = color.a;
    Color stop(int numer) =>
        color.withValues(alpha: ((numer * a) / 285).clamp(0.0, 1.0));
    return <Color>[
      color.withValues(alpha: 0),
      stop(0x60),
      stop(0xB0),
      stop(0xE8),
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (zoneHeight <= 0) return const SizedBox.shrink();

    final ramp = fadeHeight.clamp(0.0, zoneHeight);
    final stops = opacityStops(color);
    final end = zoneHeight <= 0 ? 1.0 : (ramp / zoneHeight).clamp(0.0, 1.0);
    // Even spacing across the ramp (Java `positions == null`), then clamp
    // the last stop through the rest of the zone (`TileMode.CLAMP`).
    final colors = <Color>[
      stops[0],
      stops[1],
      stops[2],
      stops[3],
      if (end < 1) stops[3],
    ];
    final positions = <double>[
      0,
      end / 3,
      end * 2 / 3,
      end,
      if (end < 1) 1,
    ];

    return IgnorePointer(
      child: SizedBox(
        height: zoneHeight,
        width: double.infinity,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: colors,
              stops: positions,
            ),
          ),
        ),
      ),
    );
  }
}
