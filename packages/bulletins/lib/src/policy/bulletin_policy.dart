import 'package:bulletins/src/bulletin/bulletin.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/physics.dart';

/// The **bulletin policy**: the layout and motion values of one platform
/// family. Plain values with no widgets and no platform reads.
///
/// Three stock families mirror the reference clients: [BulletinPolicy.android]
/// (a card at the bottom that slides on a spring, swipes away and holds its
/// timer while pressed), [BulletinPolicy.ios] (a card at the bottom that fades
/// and scales, with no gestures) and [BulletinPolicy.desktop] (a toast centred
/// on the surface that fades). [BulletinPolicy.forPlatform] picks one.
///
/// Not sealed: a host changes one value by extending a stock family and
/// overriding that getter, or implements every value itself. Nothing reads
/// which family a policy is; the view reads values only. Run
/// `BulletinPolicyContract` from `package:bulletins/testing.dart` over a
/// host's policy.
///
/// The visuals that differ by more than a value (glass, blur) are not here:
/// they are the host view's builders.
@immutable
abstract base class BulletinPolicy {
  /// A policy; for subclasses.
  const BulletinPolicy();

  /// The reference Android client's values; see [BulletinPolicy$Android].
  const factory BulletinPolicy.android() = BulletinPolicy$Android;

  /// The reference iOS client's values; see [BulletinPolicy$IOS].
  const factory BulletinPolicy.ios() = BulletinPolicy$IOS;

  /// The reference desktop client's values; see [BulletinPolicy$Desktop].
  const factory BulletinPolicy.desktop() = BulletinPolicy$Desktop;

  /// The family of [platform]: Android and iOS their own, every other
  /// operating system and the web ([isWeb] wins) desktop.
  factory BulletinPolicy.forPlatform(
    TargetPlatform platform, {
    required bool isWeb,
  }) {
    if (isWeb) return const BulletinPolicy.desktop();
    return switch (platform) {
      TargetPlatform.android => const BulletinPolicy.android(),
      TargetPlatform.iOS => const BulletinPolicy.ios(),
      TargetPlatform.macOS ||
      TargetPlatform.windows ||
      TargetPlatform.linux ||
      TargetPlatform.fuchsia => const BulletinPolicy.desktop(),
    };
  }

  /// The family of the running app.
  factory BulletinPolicy.current() =>
      BulletinPolicy.forPlatform(defaultTargetPlatform, isWeb: kIsWeb);

  // --- Timing ---

  /// The timeout of a bulletin of [duration] class.
  Duration timeoutOf(BulletinDurationClass duration);

  /// The timeout of a bulletin that lasts [duration]: the class through
  /// [timeoutOf], an exact time as given, and none (null) until dismissed.
  @nonVirtual
  Duration? timeoutFor(BulletinDuration duration) => switch (duration) {
    BulletinDuration$Class(:final value) => timeoutOf(value),
    BulletinDuration$Exactly(:final timeout) => timeout,
    BulletinDuration$UntilDismissed() => null,
  };

  // --- Layout ---

  /// Where a bulletin appears when it names no placement.
  BulletinPlacement get placement;

  /// The space between the card and the edges of the area it may take (the
  /// surface less its obstruction).
  EdgeInsets get margin;

  /// The card's shortest height.
  double get minHeight;

  /// The card's corner radius.
  double get cornerRadius;

  /// The card's widest width; null for the whole width the margin leaves.
  double? get maxWidth;

  /// Whether the card is drawn only inside the area the obstruction leaves,
  /// so it enters from behind the bottom obstruction rather than over it.
  bool get clipsAtObstruction;

  // --- Motion ---

  /// How the card enters and leaves.
  BulletinTransition get transition;

  /// The spring the card follows the obstruction with when it moves; null to
  /// jump.
  SpringDescription? get followSpring;

  // --- Gestures ---

  /// Whether a horizontal drag can throw the card away.
  bool get swipeToDismiss;

  /// The share of the card's width a released drag must pass to dismiss.
  double get swipeDismissFraction;

  /// The horizontal speed, in logical pixels per second, over which a
  /// released drag dismisses whatever its distance.
  double get swipeFlingVelocity;

  /// Whether pressing the card holds its timer until the press ends.
  bool get pauseOnPress;

  /// The card's scale while pressed; 1 for no press feedback.
  double get pressScale;
}

/// How a bulletin enters and leaves.
@immutable
sealed class BulletinTransition {
  const BulletinTransition._();

  /// Slides in from the edge it sits on and back out, on a spring of
  /// [stiffness] and [dampingRatio] (unit mass). Physical: no motion role
  /// times it.
  const factory BulletinTransition.slide({
    double stiffness,
    double dampingRatio,
  }) = BulletinTransition$Slide;

  /// Fades in while growing from [fromScale], and fades out while shrinking
  /// back to it, timed by the `bulletinShow` and `bulletinHide` motion roles.
  const factory BulletinTransition.fadeScale({double fromScale}) =
      BulletinTransition$FadeScale;

  /// Fades in and out, timed by the `bulletinShow` and `bulletinHide` motion
  /// roles.
  const factory BulletinTransition.fade() = BulletinTransition$Fade;
}

/// The [BulletinTransition.slide] transition.
final class BulletinTransition$Slide extends BulletinTransition {
  /// A slide on a spring; the defaults are the reference Android client's.
  const BulletinTransition$Slide({
    this.stiffness = 400,
    this.dampingRatio = 0.8,
  }) : super._();

  /// The spring's stiffness.
  final double stiffness;

  /// The spring's damping as a ratio of critical damping.
  final double dampingRatio;

  /// The spring, of unit mass.
  SpringDescription get spring => SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: stiffness,
    ratio: dampingRatio,
  );

  @override
  bool operator ==(Object other) =>
      other is BulletinTransition$Slide &&
      other.stiffness == stiffness &&
      other.dampingRatio == dampingRatio;

  @override
  int get hashCode =>
      Object.hash(BulletinTransition$Slide, stiffness, dampingRatio);
}

/// The [BulletinTransition.fadeScale] transition.
final class BulletinTransition$FadeScale extends BulletinTransition {
  /// A fade and scale; the default start scale is the reference iOS
  /// client's.
  const BulletinTransition$FadeScale({this.fromScale = 0.96}) : super._();

  /// The scale the card grows from and shrinks to.
  final double fromScale;

  @override
  bool operator ==(Object other) =>
      other is BulletinTransition$FadeScale && other.fromScale == fromScale;

  @override
  int get hashCode => Object.hash(BulletinTransition$FadeScale, fromScale);
}

/// The [BulletinTransition.fade] transition.
final class BulletinTransition$Fade extends BulletinTransition {
  /// A fade.
  const BulletinTransition$Fade() : super._();

  @override
  bool operator ==(Object other) => other is BulletinTransition$Fade;

  @override
  int get hashCode => (BulletinTransition$Fade).hashCode;
}

// --- Stock families ---

/// The reference Android client's bulletin (`Bulletin`): a card at the
/// bottom above the composer and keyboard, sliding on a spring, thrown away
/// by a horizontal swipe, its timer held while pressed.
base class BulletinPolicy$Android extends BulletinPolicy {
  /// The Android family.
  const BulletinPolicy$Android();

  @override
  Duration timeoutOf(BulletinDurationClass duration) => switch (duration) {
    BulletinDurationClass.short => const Duration(milliseconds: 1500),
    BulletinDurationClass.long => const Duration(milliseconds: 2750),
    BulletinDurationClass.prolonged => const Duration(milliseconds: 5000),
  };

  @override
  BulletinPlacement get placement => BulletinPlacement.bottom;

  /// The reference lays the card out with 16 dp of padding and draws its
  /// background inset by 8 on each side, so the visible card sits 8 from
  /// every edge.
  @override
  EdgeInsets get margin => const EdgeInsets.all(8);

  @override
  double get minHeight => 48;

  @override
  double get cornerRadius => 16;

  /// The reference matches the parent on a phone and wraps on a tablet or in
  /// landscape; 400 caps a wide window without changing a phone.
  @override
  double? get maxWidth => 400;

  @override
  bool get clipsAtObstruction => true;

  @override
  BulletinTransition get transition => const BulletinTransition.slide();

  @override
  SpringDescription? get followSpring =>
      SpringDescription.withDampingRatio(mass: 1, stiffness: 900, ratio: 1);

  @override
  bool get swipeToDismiss => true;

  @override
  double get swipeDismissFraction => 1 / 3;

  @override
  double get swipeFlingVelocity => 2000;

  @override
  bool get pauseOnPress => true;

  @override
  double get pressScale => 0.98;
}

/// The reference iOS client's undo overlay (`UndoOverlayController`): a card
/// at the bottom that fades and scales in and out, with no swipe and no
/// pause.
base class BulletinPolicy$IOS extends BulletinPolicy {
  /// The iOS family.
  const BulletinPolicy$IOS();

  /// A plain notice stays 3 s there (copy, link copied, media saved), one
  /// with a button 5 s.
  @override
  Duration timeoutOf(BulletinDurationClass duration) => switch (duration) {
    BulletinDurationClass.short => const Duration(seconds: 3),
    BulletinDurationClass.long => const Duration(seconds: 3),
    BulletinDurationClass.prolonged => const Duration(seconds: 5),
  };

  @override
  BulletinPlacement get placement => BulletinPlacement.bottom;

  @override
  EdgeInsets get margin => const EdgeInsets.fromLTRB(12, 8, 12, 8);

  @override
  double get minHeight => 50;

  @override
  double get cornerRadius => 25;

  @override
  double? get maxWidth => null;

  @override
  bool get clipsAtObstruction => false;

  @override
  BulletinTransition get transition => const BulletinTransition.fadeScale();

  @override
  SpringDescription? get followSpring =>
      SpringDescription.withDampingRatio(mass: 1, stiffness: 900, ratio: 1);

  @override
  bool get swipeToDismiss => false;

  @override
  double get swipeDismissFraction => 1 / 3;

  @override
  double get swipeFlingVelocity => 2000;

  @override
  bool get pauseOnPress => false;

  @override
  double get pressScale => 1;
}

/// The reference desktop client's toast (`Ui::Toast`): centred on the
/// surface, fading in and out, no gestures.
///
/// Its default timeout, margins and height live in a toolkit the reference
/// checkout does not include; the short timeout and the metrics here are
/// unverified, the long and prolonged ones are its call sites' 4 s and 5 s.
base class BulletinPolicy$Desktop extends BulletinPolicy {
  /// The desktop family.
  const BulletinPolicy$Desktop();

  @override
  Duration timeoutOf(BulletinDurationClass duration) => switch (duration) {
    BulletinDurationClass.short => const Duration(milliseconds: 1500),
    BulletinDurationClass.long => const Duration(seconds: 4),
    BulletinDurationClass.prolonged => const Duration(seconds: 5),
  };

  @override
  BulletinPlacement get placement => BulletinPlacement.center;

  @override
  EdgeInsets get margin => const EdgeInsets.all(16);

  @override
  double get minHeight => 40;

  @override
  double get cornerRadius => 9;

  @override
  double? get maxWidth => 380;

  @override
  bool get clipsAtObstruction => false;

  @override
  BulletinTransition get transition => const BulletinTransition.fade();

  @override
  SpringDescription? get followSpring => null;

  @override
  bool get swipeToDismiss => false;

  @override
  double get swipeDismissFraction => 1 / 3;

  @override
  double get swipeFlingVelocity => 2000;

  @override
  bool get pauseOnPress => false;

  @override
  double get pressScale => 1;
}
