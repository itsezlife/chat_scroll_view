import 'package:bulletins/src/bulletin/bulletin.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

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

  /// Null (the default): the card fills the width up to [maxWidth], as a
  /// phone card does. A width: the card takes its content's width, no
  /// narrower than this and no wider than [maxWidth], as a desktop toast
  /// does.
  double? get minWidth => null;

  /// The space between the card's edge and its content.
  EdgeInsets get contentPadding;

  /// The width of the leading slot, when the bulletin has a leading.
  double get leadingWidth;

  /// The size of a leading icon or animation inside its slot.
  double get iconSize;

  /// The text size of a message without a title.
  double get messageTextSize;

  /// The text size of a title.
  double get titleTextSize;

  /// The text size of a message under a title.
  double get subtitleTextSize;

  /// Whether the card is drawn only inside the area the obstruction leaves,
  /// so it enters from behind the bottom obstruction rather than over it.
  bool get clipsAtObstruction;

  // --- Motion ---

  /// How the card enters and leaves at the policy's [placement].
  BulletinTransition get transition;

  /// How a card at [placement] enters and leaves; [transition] unless a
  /// family moves cards differently by where they sit (the desktop toast
  /// fades in the middle and slides at an edge).
  BulletinTransition transitionAt(BulletinPlacement placement) => transition;

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

  /// Whether a card with nothing to press (no action, no body tap, no link)
  /// lets pointers through to the surface under it, as the desktop toast
  /// does, instead of catching them. False by default.
  bool get passesThroughWhenInert => false;
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
  /// back to it. [enter] and [exit] time the fade and the scale apart; a
  /// null one times both by the `bulletinShow` or `bulletinHide` motion role.
  const factory BulletinTransition.fadeScale({
    double fromScale,
    BulletinFadeScaleMotion? enter,
    BulletinFadeScaleMotion? exit,
  }) = BulletinTransition$FadeScale;

  /// Fades in and out over [enter] and [exit]; a null one is timed by the
  /// `bulletinShow` or `bulletinHide` motion role.
  const factory BulletinTransition.fade({MotionSpec? enter, MotionSpec? exit}) =
      BulletinTransition$Fade;

  /// Slides in from the edge it sits on over [enter] and back out over
  /// [exit], without fading.
  const factory BulletinTransition.timedSlide({
    required MotionSpec enter,
    required MotionSpec exit,
  }) = BulletinTransition$TimedSlide;
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
  const BulletinTransition$FadeScale({
    this.fromScale = 0.96,
    this.enter,
    this.exit,
  }) : super._();

  /// The scale the card grows from and shrinks to.
  final double fromScale;

  /// How the fade and the scale run in; null for the `bulletinShow` role on
  /// both.
  final BulletinFadeScaleMotion? enter;

  /// How they run out; null for the `bulletinHide` role on both.
  final BulletinFadeScaleMotion? exit;

  @override
  bool operator ==(Object other) =>
      other is BulletinTransition$FadeScale &&
      other.fromScale == fromScale &&
      other.enter == enter &&
      other.exit == exit;

  @override
  int get hashCode =>
      Object.hash(BulletinTransition$FadeScale, fromScale, enter, exit);
}

/// The two clocks of one direction of a [BulletinTransition.fadeScale]: the
/// fade and the scale, each with its own duration and curve.
///
/// The reference iOS client runs them apart (a 0.3 s fade under a 0.5 s
/// scale), which one motion role cannot say. Both start together; the card
/// has entered when the longer one ends, and has left when the fade ends,
/// since nothing is visible after it.
@immutable
final class BulletinFadeScaleMotion {
  /// A fade on [opacity] and a scale on [scale].
  const BulletinFadeScaleMotion({required this.opacity, required this.scale});

  /// The fade's duration and curve.
  final MotionSpec opacity;

  /// The scale's duration and curve.
  final MotionSpec scale;

  @override
  bool operator ==(Object other) =>
      other is BulletinFadeScaleMotion &&
      other.opacity == opacity &&
      other.scale == scale;

  @override
  int get hashCode => Object.hash(opacity, scale);
}

/// The [BulletinTransition.fade] transition.
final class BulletinTransition$Fade extends BulletinTransition {
  /// A fade over [enter] and [exit], or the motion roles' times.
  const BulletinTransition$Fade({this.enter, this.exit}) : super._();

  /// The fade in; null for the `bulletinShow` motion role.
  final MotionSpec? enter;

  /// The fade out; null for the `bulletinHide` motion role.
  final MotionSpec? exit;

  @override
  bool operator ==(Object other) =>
      other is BulletinTransition$Fade &&
      other.enter == enter &&
      other.exit == exit;

  @override
  int get hashCode => Object.hash(BulletinTransition$Fade, enter, exit);
}

/// The [BulletinTransition.timedSlide] transition.
final class BulletinTransition$TimedSlide extends BulletinTransition {
  /// A slide over [enter] and [exit].
  const BulletinTransition$TimedSlide({required this.enter, required this.exit})
    : super._();

  /// The slide in.
  final MotionSpec enter;

  /// The slide out.
  final MotionSpec exit;

  @override
  bool operator ==(Object other) =>
      other is BulletinTransition$TimedSlide &&
      other.enter == enter &&
      other.exit == exit;

  @override
  int get hashCode => Object.hash(BulletinTransition$TimedSlide, enter, exit);
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

  @override
  EdgeInsets get contentPadding =>
      const EdgeInsets.symmetric(horizontal: 12, vertical: 8);

  /// The reference's 56 dp icon box, less the 8 the card is inset by.
  @override
  double get leadingWidth => 48;

  @override
  double get iconSize => 24;

  @override
  double get messageTextSize => 15;

  @override
  double get titleTextSize => 14;

  @override
  double get subtitleTextSize => 13;

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

/// The reference iOS client's undo overlay (`UndoOverlayController`): a
/// blurred card at the bottom (or top) that fades and scales in and out, with
/// no swipe and no pause.
///
/// The constructor takes the reference's per-overlay `Appearance` and
/// `elevatedLayout` (`UndoOverlayController.swift:86-98`), which here belong
/// to the surface: [sideInset], [bottomInset], [elevated] and [narrow].
///
/// Line numbers below are in `UndoOverlayControllerNode.swift` of the
/// reference, `submodules/UndoUI`.
base class BulletinPolicy$IOS extends BulletinPolicy {
  /// The iOS family.
  const BulletinPolicy$IOS({
    this.sideInset = 12,
    this.bottomInset,
    this.elevated = false,
    this.narrow = false,
  });

  /// The space between the card and the area's edges, on every side
  /// (`sideInset ?? 12`, :1936; the same value spaces it from the bottom and
  /// the top, :2008, :2016).
  final double sideInset;

  /// Extra space under a bottom card, over [sideInset]; null for none, or
  /// [elevatedInset] when [elevated]. Wins over [elevated] (:1996-1999).
  final double? bottomInset;

  /// Whether the surface has a bar under the bulletin that the obstruction
  /// does not include (a tab bar, an input panel): the card then sits
  /// [elevatedInset] higher (`elevatedLayout`, :1998-1999).
  final bool elevated;

  /// Whether the card is [narrowWidth] wide instead of the full width
  /// (`isNarrow`, :2004-2005).
  final bool narrow;

  /// The rise of an [elevated] card (:1999).
  static const double elevatedInset = 49;

  /// The width of a [narrow] card (:2005).
  static const double narrowWidth = 210;

  /// A plain notice stays 3 s (copy :1046, link copied :355, media saved
  /// :1067, a sticker or `universal` without a link :953, :1152); one with
  /// Undo 5 s (removed chat :176, archived :204, action succeeded :332).
  /// A long text gets no more time there: copy and link copied keep 3 s
  /// whatever their length.
  @override
  Duration timeoutOf(BulletinDurationClass duration) => switch (duration) {
    BulletinDurationClass.short => const Duration(seconds: 3),
    BulletinDurationClass.long => const Duration(seconds: 3),
    BulletinDurationClass.prolonged => const Duration(seconds: 5),
  };

  @override
  BulletinPlacement get placement => BulletinPlacement.bottom;

  @override
  EdgeInsets get margin => EdgeInsets.fromLTRB(
    sideInset,
    sideInset,
    sideInset,
    sideInset + (bottomInset ?? (elevated ? elevatedInset : 0)),
  );

  /// `max(50, contentHeight)` (:1989).
  @override
  double get minHeight => 50;

  /// :1576, drawn with the continuous corner curve (:1700).
  @override
  double get cornerRadius => 25;

  /// The text block has 10 above and 10 below it (`contentHeight = 20 +
  /// ...`, :1934); the action label ends 16 from the right edge (`rightInset`,
  /// :1933). The left 16 applies only without a leading, a case the
  /// reference does not have: there the text starts at the leading slot's
  /// end.
  @override
  EdgeInsets get contentPadding => const EdgeInsets.fromLTRB(16, 10, 16, 10);

  /// `leftInset` (:1918): the slot runs from the card's edge and the text
  /// starts at its end; the leading is centred in it.
  @override
  double get leadingWidth => 50;

  /// An animated leading's frame (32 by 32, :2138).
  @override
  double get iconSize => 32;

  /// Every text is 14: regular, semibold for the title (:149-150, :194).
  @override
  double get messageTextSize => 14;

  @override
  double get titleTextSize => 14;

  @override
  double get subtitleTextSize => 14;

  @override
  double? get maxWidth => narrow ? narrowWidth : null;

  @override
  bool get clipsAtObstruction => false;

  /// In: opacity 0 to 1 in 0.3 s (the default ease-in-ease-out) and scale
  /// 0.96 to 1 in 0.5 s on the spring curve (:2208-2212). Out: opacity to 0
  /// in 0.25 s ease-out and scale to 0.96 in 0.5 s on the spring curve,
  /// gone when the fade ends (:2242-2247).
  @override
  BulletinTransition get transition => const BulletinTransition.fadeScale(
    enter: BulletinFadeScaleMotion(
      opacity: MotionSpec(Duration(milliseconds: 300), Curves.easeInOut),
      scale: MotionSpec(Duration(milliseconds: 500), springCurve),
    ),
    exit: BulletinFadeScaleMotion(
      opacity: MotionSpec(Duration(milliseconds: 250), Curves.easeOut),
      scale: MotionSpec(Duration(milliseconds: 500), springCurve),
    ),
  );

  /// The reference's `kCAMediaTimingFunctionSpring` at 0.5 s is a Core
  /// Animation spring whose constants live outside the reference checkout;
  /// its own non-spring fallback draws it as this cubic
  /// (`Display/Source/ListViewAnimation.swift:103`).
  static const Curve springCurve = Cubic(0.23, 1, 0.32, 1);

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

  /// The overlay takes touches only with an Undo or a link; otherwise the
  /// screen under it gets them (:1596-1605).
  @override
  bool get passesThroughWhenInert => true;
}

/// The reference desktop client's toast (`Ui::Toast` in the toolkit
/// `lib_ui`, its `defaultMultilineToast` style, which a toast takes when the
/// caller names none): centred on the surface, or attached to the top or
/// bottom edge; as wide as its text between 160 and 360; it fades in over
/// 200 ms and out over 1000 ms in the middle and slides 160 ms at an edge,
/// both linear; no gestures, and pointers pass through it unless it has
/// something to press.
///
/// The short timeout is the toolkit's default of 1.5 s; the long and
/// prolonged ones are its callers' 4 s (a link copied) and 5 s (a toast with
/// a button), since every other caller keeps the default.
base class BulletinPolicy$Desktop extends BulletinPolicy {
  /// The desktop family.
  const BulletinPolicy$Desktop();

  static const MotionSpec _fadeIn = MotionSpec(
    Duration(milliseconds: 200),
    Curves.linear,
  );
  static const MotionSpec _fadeOut = MotionSpec(
    Duration(milliseconds: 1000),
    Curves.linear,
  );
  static const MotionSpec _slide = MotionSpec(
    Duration(milliseconds: 160),
    Curves.linear,
  );

  @override
  Duration timeoutOf(BulletinDurationClass duration) => switch (duration) {
    BulletinDurationClass.short => const Duration(milliseconds: 1500),
    BulletinDurationClass.long => const Duration(seconds: 4),
    BulletinDurationClass.prolonged => const Duration(seconds: 5),
  };

  @override
  BulletinPlacement get placement => BulletinPlacement.center;

  @override
  EdgeInsets get margin => const EdgeInsets.all(13);

  /// The toolkit sets no height: the text and its padding decide it. The
  /// one floor it has is an icon and its 2 px above and below.
  @override
  double get minHeight => 24;

  @override
  double get cornerRadius => 8;

  @override
  EdgeInsets get contentPadding => const EdgeInsets.fromLTRB(19, 13, 19, 12);

  /// A 20 px icon with 12 on each side; the slot takes the place of the
  /// start padding.
  @override
  double get leadingWidth => 44;

  @override
  double get iconSize => 20;

  @override
  double get messageTextSize => 13;

  @override
  double get titleTextSize => 13;

  @override
  double get subtitleTextSize => 13;

  @override
  double? get maxWidth => 360;

  @override
  double? get minWidth => 160;

  @override
  bool get clipsAtObstruction => false;

  @override
  BulletinTransition get transition => transitionAt(placement);

  @override
  BulletinTransition transitionAt(BulletinPlacement placement) =>
      switch (placement) {
        BulletinPlacement.center => const BulletinTransition.fade(
          enter: _fadeIn,
          exit: _fadeOut,
        ),
        BulletinPlacement.top || BulletinPlacement.bottom =>
          const BulletinTransition.timedSlide(enter: _slide, exit: _slide),
      };

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

  @override
  bool get passesThroughWhenInert => true;
}
