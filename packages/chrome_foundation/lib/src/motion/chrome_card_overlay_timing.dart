import 'package:chrome_foundation/src/motion/chrome_motion.dart';
import 'package:chrome_foundation/src/motion/motion_spec.dart';

/// Timing of a full-window card overlay over a list: a card of the list's
/// content with a menu under it, which scales and fades in and out about
/// its centre and follows a change of its content.
///
/// Every motion is the list's own: 250 ms on
/// [ChromeMotion.androidListCurve], so the card moves with the bubble it
/// previews. They are not `ChromeMotion` roles: one surface owns them and a
/// host tunes it through that surface's policy.
abstract final class ChromeCardOverlayTiming {
  /// The overlay coming in: opacity 0 to 1 and a scale up to 1.
  static const MotionSpec show = MotionSpec(
    Duration(milliseconds: 250),
    ChromeMotion.androidListCurve,
  );

  /// The overlay going: the reverse of [show], then it is removed.
  static const MotionSpec hide = MotionSpec(
    Duration(milliseconds: 250),
    ChromeMotion.androidListCurve,
  );

  /// The card's visible top and its centring moving to a changed content.
  static const MotionSpec offsets = MotionSpec(
    Duration(milliseconds: 250),
    ChromeMotion.androidListCurve,
  );

  /// How far [offsets] starts behind the change (50 ms): the list's own
  /// change runs first, so the card follows it.
  static const Duration offsetsDelay = Duration(milliseconds: 50);

  /// The card's list scrolling to the changed content's end.
  static const MotionSpec listScroll = MotionSpec(
    Duration(milliseconds: 250),
    ChromeMotion.androidListCurve,
  );
}
