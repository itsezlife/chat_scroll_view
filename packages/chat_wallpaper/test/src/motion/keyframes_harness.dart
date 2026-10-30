import 'package:chat_wallpaper/chat_wallpaper.dart';
import 'package:chat_wallpaper/src/motion/freeform_keyframes.dart';
import 'package:flutter_test/flutter_test.dart';

/// Lets real time run for background pixel isolates and image decodes until
/// [done] holds, failing if it never does. A keyframe takes about two rounds,
/// one for its pixels and one for its decode, so a whole ring fits with room
/// to spare.
Future<void> decode(WidgetTester tester, bool Function() done) async {
  for (var step = 0; step < 300 && !done(); step++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  expect(done(), isTrue, reason: 'decodes did not land');
}

/// A keyframe named as [FreeformKeyframes.holds] names it.
typedef Arrangement = ({int phase, int third});

/// Every keyframe of a wallpaper's ring, phase by phase.
final List<Arrangement> ring = [
  for (var phase = 0; phase < FreeformGradient.phaseCount; phase++)
    for (var third = 1; third <= FreeformKeyframes.perStep; third++)
      (phase: phase, third: third),
];

/// Keyframes of the ring [keyframes] hold right now.
Set<Arrangement> heldBy(FreeformKeyframes keyframes) => {
  for (final arrangement in ring)
    if (keyframes.holds(phase: arrangement.phase, third: arrangement.third))
      arrangement,
};

/// Whether [motion] holds every keyframe of [fill]'s ring. Only a wait
/// condition, and only for a fill something else holds: the last release
/// disposes the keyframes.
bool holdsRing(
  ChatWallpaperMotionController motion,
  ChatWallpaper$Freeform fill,
) {
  final keyframes = motion.acquireKeyframes(fill);
  try {
    return heldBy(keyframes).length == FreeformKeyframes.ringLength;
  } finally {
    motion.releaseKeyframes(fill);
  }
}
