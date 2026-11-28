import 'package:chrome_foundation/src/motion/chrome_motion.dart';
import 'package:chrome_foundation/src/motion/motion_spec.dart';

/// Timing of a full-window card overlay over a list: a card of the list's
/// content with a menu under it, which scales and fades in and out about
/// its centre and follows a change of its content.
///
/// Every move of the card is the list's own, [motion], so the card moves
/// with the content it previews. They are not `ChromeMotion` roles: one
/// surface owns them and a host tunes it through that surface's policy.
abstract final class ChromeCardOverlayTiming {
  /// The list's motion, which every move of the card takes: its open and
  /// close (opacity and scale about the centre), its visible top and
  /// centring following a changed content, and its list scrolling to the
  /// content's end. 250 ms on [ChromeMotion.androidListCurve].
  static const MotionSpec motion = MotionSpec(
    Duration(milliseconds: 250),
    ChromeMotion.androidListCurve,
  );

  /// How far the card's offsets start behind a change (50 ms): the list's
  /// own change runs first, so the card follows it.
  static const Duration offsetsDelay = Duration(milliseconds: 50);
}
