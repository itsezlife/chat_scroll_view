import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// The thumb a fast scrollbar drags: its shape and where it sits against
/// the scrollbar's edge.
@immutable
sealed class FastScrollThumb {
  const FastScrollThumb();

  /// A disc of [radius] centred [centerInset] in from the edge, so most of
  /// it lies past the edge and a half disc shows, with an up and a down
  /// chevron on it.
  const factory FastScrollThumb.tab({
    double radius,
    double centerInset,
    Size chevron,
    double chevronInset,
    double chevronOffset,
    double chevronSpread,
  }) = FastScrollThumb$Tab;

  /// A capsule [width] wide (and [activeWidth] while dragged) [edgeInset]
  /// in from the edge.
  const factory FastScrollThumb.line({
    double width,
    double activeWidth,
    double edgeInset,
  }) = FastScrollThumb$Line;
}

/// See [FastScrollThumb.tab].
final class FastScrollThumb$Tab extends FastScrollThumb {
  /// A tab thumb.
  const FastScrollThumb$Tab({
    this.radius = 24,
    this.centerInset = 7,
    this.chevron = const Size(8, 4),
    this.chevronInset = 11,
    this.chevronOffset = 7,
    this.chevronSpread = 2,
  });

  /// The disc's radius.
  final double radius;

  /// How far in from the edge the disc's centre sits.
  final double centerInset;

  /// One chevron's width and height.
  final Size chevron;

  /// How far in from the edge the chevrons' tips sit.
  final double chevronInset;

  /// How far above and below the centre each chevron's tip sits.
  final double chevronOffset;

  /// How much further apart the chevrons move while the thumb is dragged.
  final double chevronSpread;

  @override
  bool operator ==(Object other) =>
      other is FastScrollThumb$Tab &&
      other.radius == radius &&
      other.centerInset == centerInset &&
      other.chevron == chevron &&
      other.chevronInset == chevronInset &&
      other.chevronOffset == chevronOffset &&
      other.chevronSpread == chevronSpread;

  @override
  int get hashCode => Object.hash(
    radius,
    centerInset,
    chevron,
    chevronInset,
    chevronOffset,
    chevronSpread,
  );
}

/// See [FastScrollThumb.line].
final class FastScrollThumb$Line extends FastScrollThumb {
  /// A line thumb.
  const FastScrollThumb$Line({
    this.width = 3,
    this.activeWidth = 6,
    this.edgeInset = 3,
  });

  /// The capsule's width at rest.
  final double width;

  /// The capsule's width while dragged.
  final double activeWidth;

  /// The gap between the capsule and the edge.
  final double edgeInset;

  @override
  bool operator ==(Object other) =>
      other is FastScrollThumb$Line &&
      other.width == width &&
      other.activeWidth == activeWidth &&
      other.edgeInset == edgeInset;

  @override
  int get hashCode => Object.hash(width, activeWidth, edgeInset);
}

/// One animation's length and curve.
@immutable
final class FastScrollMotion {
  /// A motion over [duration] along [curve].
  const FastScrollMotion(this.duration, [this.curve = Curves.linear]);

  /// How long it runs.
  final Duration duration;

  /// Its easing.
  final Curve curve;

  @override
  bool operator ==(Object other) =>
      other is FastScrollMotion &&
      other.duration == duration &&
      other.curve == curve;

  @override
  int get hashCode => Object.hash(duration, curve);
}

/// The platform values of a fast scrollbar: the thumb, its track, when it
/// and the label show, where the label sits, how a drag starts and the
/// haptics. Colours are the host's (`FastScrollbarStyle`).
///
/// Both presets drag the same way: relative to where the finger went down,
/// the thumb's travel spanning the whole scroll range, so a press never
/// jumps the content and a drag of the whole travel scrolls end to end.
/// They differ in the rest:
///
/// | | [$Android] | [$IOS] |
/// |---|---|---|
/// | Thumb | a half disc with chevrons | a thin capsule |
/// | Thumb shown | while the host enables it | while scrolling, then 2 s |
/// | Drag starts | on a move past 8 (the platform's touch slop) | on a move past touch slop, or a 200 ms hold |
/// | Label shift while dragged | 30 | 80 |
/// | Haptics | none | at the start, and as the label changes |
@immutable
final class FastScrollbarPolicy {
  /// A policy with every value given.
  const FastScrollbarPolicy({
    required this.thumb,
    required this.thumbExtent,
    required this.trackInset,
    required this.hitWidth,
    required this.hitSlop,
    required this.thumbIdleHide,
    required this.thumbShow,
    required this.thumbHide,
    required this.labelIdleHide,
    required this.labelShow,
    required this.labelHide,
    required this.labelScaleFrom,
    required this.labelGap,
    required this.labelPadding,
    required this.labelHeight,
    required this.labelRadius,
    required this.dragShift,
    required this.dragShiftIn,
    required this.dragShiftOut,
    required this.labelChange,
    required this.labelChangeSlide,
    required this.holdToDrag,
    required this.dragStartHaptic,
    required this.labelChangeHaptic,
    required this.maxViewportFraction,
    required this.mirrorsInRtl,
    this.dragSlop,
  });

  /// The half-disc thumb that shows while the host enables it, the label
  /// beside it on scroll and drag.
  static const FastScrollbarPolicy $Android = FastScrollbarPolicy(
    thumb: FastScrollThumb.tab(),
    thumbExtent: 30,
    trackInset: 12,
    hitWidth: 25,
    hitSlop: 0,
    thumbIdleHide: null,
    thumbShow: FastScrollMotion(Duration(milliseconds: 100), Curves.easeInOut),
    thumbHide: FastScrollMotion(Duration(milliseconds: 100), Curves.easeInOut),
    labelIdleHide: Duration(seconds: 2),
    labelShow: FastScrollMotion(Duration(milliseconds: 120)),
    labelHide: FastScrollMotion(Duration(milliseconds: 120)),
    labelScaleFrom: 0.7,
    labelGap: 35,
    labelPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    labelHeight: null,
    labelRadius: 14,
    dragShift: 30,
    dragShiftIn: FastScrollMotion(Duration(milliseconds: 120)),
    dragShiftOut: FastScrollMotion(Duration(milliseconds: 120)),
    labelChange: FastScrollMotion(Duration(milliseconds: 150)),
    labelChangeSlide: 15,
    holdToDrag: null,
    dragSlop: 8,
    dragStartHaptic: false,
    labelChangeHaptic: false,
    maxViewportFraction: null,
    mirrorsInRtl: false,
  );

  /// The thin capsule that shows while scrolling, the label beside it, both
  /// gone 2 s after the scroll stops.
  static const FastScrollbarPolicy $IOS = FastScrollbarPolicy(
    thumb: FastScrollThumb.line(),
    thumbExtent: 44,
    trackInset: 3,
    hitWidth: 13,
    hitSlop: 2,
    thumbIdleHide: Duration(seconds: 2),
    thumbShow: FastScrollMotion(Duration(milliseconds: 300), Curves.easeInOut),
    thumbHide: FastScrollMotion(Duration(milliseconds: 300), Curves.easeInOut),
    labelIdleHide: Duration(seconds: 2),
    labelShow: FastScrollMotion(Duration(milliseconds: 200), Curves.easeInOut),
    labelHide: FastScrollMotion(Duration(milliseconds: 200), Curves.easeInOut),
    labelScaleFrom: 1,
    labelGap: 12,
    labelPadding: EdgeInsets.symmetric(horizontal: 13),
    labelHeight: 32,
    labelRadius: 16,
    dragShift: 80,
    dragShiftIn: FastScrollMotion(
      Duration(milliseconds: 100),
      Curves.easeInOut,
    ),
    dragShiftOut: FastScrollMotion(
      Duration(milliseconds: 200),
      Curves.easeInOut,
    ),
    labelChange: FastScrollMotion(
      Duration(milliseconds: 200),
      Curves.easeInOut,
    ),
    labelChangeSlide: 12,
    holdToDrag: Duration(milliseconds: 200),
    dragStartHaptic: true,
    labelChangeHaptic: true,
    maxViewportFraction: 0.55,
    mirrorsInRtl: false,
  );

  /// [$IOS] on iOS and macOS, [$Android] elsewhere; [platform] or
  /// [defaultTargetPlatform].
  static FastScrollbarPolicy forPlatform({TargetPlatform? platform}) =>
      switch (platform ?? defaultTargetPlatform) {
        TargetPlatform.iOS || TargetPlatform.macOS => $IOS,
        TargetPlatform.android ||
        TargetPlatform.fuchsia ||
        TargetPlatform.windows ||
        TargetPlatform.linux => $Android,
      };

  /// The thumb's shape.
  final FastScrollThumb thumb;

  /// The thumb's length along the track.
  final double thumbExtent;

  /// The gap between each end of the track and the thumb at that end.
  final double trackInset;

  /// How far in from the edge a press takes the thumb.
  final double hitWidth;

  /// How far above and below the thumb a press still takes it.
  final double hitSlop;

  /// How long after the last scroll the thumb hides; null keeps it while
  /// the host enables it.
  final Duration? thumbIdleHide;

  /// The thumb's fade in.
  final FastScrollMotion thumbShow;

  /// The thumb's fade out.
  final FastScrollMotion thumbHide;

  /// How long after the last scroll, or the drag's end, the label hides.
  final Duration labelIdleHide;

  /// The label's appearance.
  final FastScrollMotion labelShow;

  /// The label's disappearance.
  final FastScrollMotion labelHide;

  /// The label's scale as it starts to appear, about its end by the thumb.
  final double labelScaleFrom;

  /// The gap between the label's end and the edge, at rest.
  final double labelGap;

  /// The space around the label's text.
  final EdgeInsets labelPadding;

  /// The label's height; null for its text's plus [labelPadding].
  final double? labelHeight;

  /// The label's corner radius.
  final double labelRadius;

  /// How much further from the edge the label moves while the thumb is
  /// dragged, clear of the finger.
  final double dragShift;

  /// The label's move out as a drag starts.
  final FastScrollMotion dragShiftIn;

  /// The label's move back as a drag ends.
  final FastScrollMotion dragShiftOut;

  /// The roll from one label text to the next.
  final FastScrollMotion labelChange;

  /// How far the old text slides out and the new one in.
  final double labelChangeSlide;

  /// A press held this long starts the drag without a move; null for a
  /// move past touch slop only.
  final Duration? holdToDrag;

  /// How far a press on the thumb moves before the drag starts; null for
  /// the gesture settings' touch slop. Below the scrollable's own slop, a
  /// press on the thumb takes the drag before the content can.
  final double? dragSlop;

  /// Whether a drag's start plays an impact haptic.
  final bool dragStartHaptic;

  /// Whether each change of the label while dragging plays a selection
  /// haptic.
  final bool labelChangeHaptic;

  /// The scrollbar hides while the viewport shows this fraction of the
  /// content or more; null shows it whenever the content scrolls.
  final double? maxViewportFraction;

  /// Whether a right-to-left ambient direction puts the scrollbar on the
  /// left edge. The date presets stay on the right.
  final bool mirrorsInRtl;
}
