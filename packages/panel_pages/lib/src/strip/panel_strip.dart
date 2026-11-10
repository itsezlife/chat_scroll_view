import 'dart:async';
import 'dart:ui' show lerpDouble;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/widgets.dart';

/// The mechanism a page's strip of tabs is built from: the emoji strip and
/// the stickers strip are one strip in one look, with two sets of metrics.
///
/// One row [PanelStripMetrics.height] tall, a tab every
/// [PanelStripMetrics.pitch] from [PanelStripMetrics.padH] in; a pill
/// [PanelStripMetrics.pillSide] tall marks the active tab, sliding to the
/// next in 350 ms ease-out quint and swelling half way; a pack's tab is its
/// cover, over a stand-in in the theme until the cover has anything to show.
///
/// What the two strips do differently is a field of
/// [PanelStripMetrics]: the sizes, the swell and whether a cover plays. What
/// only one of them has (the emoji strip's folding group, each strip's rule
/// for scrolling a tab into view, the stickers strip's directional layout)
/// stays in that strip.
///
/// Internal to the package: nothing here is exported.
@immutable
final class PanelStripMetrics {
  /// Metrics with every measure given.
  const PanelStripMetrics({
    required this.tabWidth,
    required this.tabHeight,
    required this.gap,
    required this.padH,
    required this.iconSize,
    required this.coverSize,
    required this.swell,
    required this.coverPlays,
  });

  /// Height of either strip: `createFrame(MATCH_PARENT, 36)`.
  static const double height = 36;

  /// Side of the pill at rest, in both strips.
  static const double pillSide = 30;

  /// The pill's slide: `currentPositionAnimated` and `selectAnimator`, 350 ms.
  static const Duration slideDuration = Duration(milliseconds: 350);

  /// A scroll that brings a tab into view.
  static const Duration scrollDuration = Duration(milliseconds: 250);

  /// The curve of every strip motion, `CubicBezierInterpolator.EASE_OUT_QUINT`.
  static const Curve curve = Curves.easeOutQuint;

  /// Width of a tab's touch area.
  final double tabWidth;

  /// Height of a tab's touch area, centred in the strip.
  final double tabHeight;

  /// Space between two tabs.
  final double gap;

  /// Inset of the first tab from either end of the row.
  final double padH;

  /// Side of a chrome icon in a tab.
  final double iconSize;

  /// Side of a pack's cover in a tab.
  final double coverSize;

  /// How the pill swells as it slides.
  final PanelStripSwell swell;

  /// Whether a cover plays (an animated cover loops while its tab is in view)
  /// or is a still of its first frame.
  final bool coverPlays;

  /// From one tab to the next.
  double get pitch => tabWidth + gap;
}

/// How the pill changes shape on its way from tab to tab: widest and flattest
/// half way, its rest size at either end.
enum PanelStripSwell {
  /// `isMiddle = 4t(1 - t)`, the width times
  /// `1 + .3 isMiddle`, the height times `1 - .05 isMiddle`.
  emoji,

  /// The stickers swell: `far = |.5 - t| 2`, the width
  /// times `1.25 - .25 far`, the height times `.9 + .1 far`.
  stickers;

  /// [rest] when the slide is [progress] of its way (already eased).
  Size apply(Size rest, double progress) {
    switch (this) {
      case PanelStripSwell.emoji:
        final middle = 4 * progress * (1 - progress);
        return Size(
          rest.width * (1 + middle * .3),
          rest.height * (1 - middle * .05),
        );
      case PanelStripSwell.stickers:
        final far = (0.5 - progress).abs() * 2;
        return Size(
          rest.width * (1.25 - .25 * far),
          rest.height * (.9 + .1 * far),
        );
    }
  }
}

/// Where the tabs of a strip are, in the row's start-to-end coordinates.
///
/// Tabs are [PanelStripMetrics.tabWidth] wide unless [widthOf] says
/// otherwise (the emoji strip's group is as wide as it is open).
@immutable
final class PanelStripRow {
  /// A row of [tabCount] tabs.
  const PanelStripRow(this.metrics, this.tabCount, {this.widthOf});

  /// The strip's measures.
  final PanelStripMetrics metrics;

  /// How many tabs the row has.
  final int tabCount;

  /// The width of the tab at an index, or null for every tab
  /// [PanelStripMetrics.tabWidth].
  final double Function(int index)? widthOf;

  double _width(int index) => widthOf?.call(index) ?? metrics.tabWidth;

  /// The touch area of the tab at [index].
  Rect boundsOf(int index) {
    var x = metrics.padH;
    for (var i = 0; i < index; i++) {
      x += _width(i) + metrics.gap;
    }
    return Rect.fromLTWH(
      x,
      (PanelStripMetrics.height - metrics.tabHeight) / 2,
      _width(index),
      metrics.tabHeight,
    );
  }

  /// The whole row, the inset at both ends included.
  double get width => tabCount == 0
      ? metrics.padH * 2
      : boundsOf(tabCount - 1).right + metrics.padH;

  // The pill at rest on the tab at [index]: [PanelStripMetrics.pillSide]
  // tall, as wide as the tab less what a tab is wider than the pill (a tab
  // of the stickers strip is 33 wide under a 30 pill; the emoji strip's open
  // group is under a pill as wide as it).
  Rect _restOf(int index) {
    final bounds = boundsOf(index);
    final narrower = metrics.tabWidth - PanelStripMetrics.pillSide;
    return Rect.fromCenter(
      center: bounds.center,
      width: bounds.width - narrower,
      height: PanelStripMetrics.pillSide,
    );
  }

  /// The pill where [slide] has it: between the tabs it slides through, in
  /// the shape [PanelStripMetrics.swell] gives it there.
  Rect pillAt(PanelStripSlide slide) {
    final at = slide.at;
    final low = at.floor().clamp(0, tabCount - 1);
    final high = at.ceil().clamp(0, tabCount - 1);
    final rest = Rect.lerp(_restOf(low), _restOf(high), at - at.floor())!;
    final size = metrics.swell.apply(rest.size, slide.progress);
    return Rect.fromCenter(
      center: rest.center,
      width: size.width,
      height: size.height,
    );
  }

  /// The tabs a viewport of [metrics] over the row shows, in part or whole,
  /// for a row of tabs [PanelStripMetrics.tabWidth] wide.
  PanelStripRange rangeOf(ScrollMetrics viewport) {
    final pitch = metrics.pitch;
    final from = viewport.pixels - metrics.padH;
    return PanelStripRange(
      (from / pitch).floor().clamp(0, tabCount),
      ((from + viewport.viewportDimension) / pitch).ceil().clamp(0, tabCount),
    );
  }
}

/// The tabs from [start] up to [end], not included: those a strip's viewport
/// shows.
@immutable
final class PanelStripRange {
  /// The tabs from [start] up to [end].
  const PanelStripRange(this.start, this.end);

  /// Before the first layout: nothing shows yet.
  static const PanelStripRange none = PanelStripRange(0, 0);

  /// The first tab shown.
  final int start;

  /// The tab after the last one shown.
  final int end;

  /// Whether the tab at [index] shows.
  bool contains(int index) => index >= start && index < end;

  @override
  bool operator ==(Object other) =>
      other is PanelStripRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}

/// The pill's slide from tab to tab, in tab indices.
///
/// Retargets from where the pill is: a new target mid-way starts a whole slide from the
/// fraction it is at. The controller runs from 0 and the curve eases its
/// time, so a slide eases out whichever way it goes.
final class PanelStripSlide {
  /// A slide driven by a ticker of [vsync].
  PanelStripSlide({required TickerProvider vsync})
    : controller = AnimationController(
        vsync: vsync,
        duration: PanelStripMetrics.slideDuration,
      );

  /// The slide's clock: listen to it to follow the pill, run it from 0 to
  /// slide.
  final AnimationController controller;

  double _from = 0;
  double _to = 0;
  bool _placed = false;

  /// How far the slide is, eased: 0 at its start, 1 at its end.
  double get progress => PanelStripMetrics.curve.transform(controller.value);

  /// Where the pill is, in tab indices (a fraction while it slides).
  double get at => lerpDouble(_from, _to, progress)!;

  /// Whether the pill has been placed on a tab.
  bool get placed => _placed;

  /// The tab the pill goes to.
  double get target => _to;

  /// Sends the pill to the tab at [index], sliding when [moving], placing it
  /// at once otherwise. Returns whether it moved: a pill already headed for
  /// [index] stays as it is, since a slide from a tab to itself would still
  /// swell it at the middle of its way.
  bool aim(int index, {required bool moving}) {
    if (_placed && index.toDouble() == _to) return false;
    final now = at;
    _from = moving ? now : index.toDouble();
    _to = index.toDouble();
    _placed = true;
    if (moving) {
      unawaited(controller.forward(from: 0));
    } else {
      controller.value = 1;
    }
    return true;
  }

  /// Gives the clock back.
  void dispose() => controller.dispose();

  /// Whether strip motion lands at once for [context]: the system's disabled
  /// animations, or a host whose selection slide is instant.
  static bool isStill(BuildContext context) {
    final motion = ChromeMotionScope.maybeOf(context);
    return MediaQuery.maybeDisableAnimationsOf(context) == true ||
        motion?.specOf(MotionRole.selectionSlide).duration == Duration.zero;
  }

  /// Scrolls [controller] to [to], over [PanelStripMetrics.scrollDuration]
  /// when [animate], at once otherwise; nothing within half a pixel of it.
  static void scroll(
    ScrollController controller,
    double to, {
    required bool animate,
  }) {
    if ((controller.offset - to).abs() < .5) return;
    if (animate) {
      unawaited(
        controller.animateTo(
          to,
          duration: PanelStripMetrics.scrollDuration,
          curve: PanelStripMetrics.curve,
        ),
      );
    } else {
      controller.jumpTo(to);
    }
  }
}

/// The pill: a stadium in the idle icon colour at a low alpha, so the wash is
/// a tint of the icons it sits under.
class PanelStripPill extends StatelessWidget {
  /// The pill of a strip in [tokens].
  const PanelStripPill({required this.tokens, required this.height, super.key});

  /// The panel's colours.
  final PanelTokens tokens;

  /// The pill's height now, for its round ends.
  final double height;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(height / 2),
      color: tokens.categoryIcon.withValues(
        alpha: tokens.categoryIcon.a * 0.18,
      ),
    ),
  );
}

/// A tab's chrome icon, easing between the idle and the selected colour over
/// [duration].
class PanelStripIcon extends StatelessWidget {
  /// [icon], [size] square, in the colour of [selected].
  const PanelStripIcon({
    required this.icon,
    required this.size,
    required this.selected,
    required this.tokens,
    required this.duration,
    super.key,
  });

  /// What to draw.
  final ChromeIconId icon;

  /// Side of the icon.
  final double size;

  /// Whether the tab is the active one.
  final bool selected;

  /// The panel's colours.
  final PanelTokens tokens;

  /// How long the colour takes to change.
  final Duration duration;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween<double>(end: selected ? 1 : 0),
    duration: duration,
    curve: PanelStripMetrics.curve,
    builder: (context, t, _) => ChromeIcon(
      icon,
      size: size,
      color: Color.lerp(tokens.categoryIcon, tokens.categoryIconSelected, t),
    ),
  );
}

/// A pack's cover in a tab, [size] square.
///
/// ## Stand-in
///
/// Until the cover has anything to show, the tab draws [standIn], a faint
/// rounded square in the idle icon colour, never the scope's media fill
/// (every surface of the scope shares that one, and its colour is the
/// host's). The stickers strip draws the sticker's outline in the empty-list
/// placeholder colour at 0.2; an outline is metadata this package never
/// sees, so the shape is the square, and the colour the panel's idle icon,
/// the strip's own quiet colour.
///
/// ## Playing
///
/// A cover that [plays] is the whole content, looping on the shared clock
/// and decoded at its size on the screen as every animated cell is, and
/// plays only while [inView] holds [index] (a tab scrolled away neither
/// repaints nor keeps its frame lease). While the panel's tickers are off (it
/// moves, or is kept mounted while hidden) a cover holds its frame and its
/// lease, as the grid's cells do, so a panel shown again shows the frames it
/// left on at once. One that does not play is a still of its first frame: a
/// still entry holds no decoder. The view repaints through its
/// binding, so the strip is never rebuilt for a frame.
class PanelStripCover extends StatelessWidget {
  /// [content] from [scope].
  const PanelStripCover({
    required this.content,
    required this.scope,
    required this.size,
    required this.plays,
    required this.tokens,
    this.radius,
    this.index = 0,
    this.inView,
    super.key,
  });

  /// The stand-in of a cover with nothing to show yet.
  static const AssetPaintable standIn = SoftPlaceholder();

  /// The cover.
  final ContentKey content;

  /// Where it is drawn from.
  final AssetCacheScope scope;

  /// Side of the cover.
  final double size;

  /// Whether it plays, or is a still of its first frame.
  final bool plays;

  /// The panel's colours; the stand-in is in its idle icon colour.
  final PanelTokens tokens;

  /// The radius the cover is clipped to, or null for none.
  final double? radius;

  /// Where the tab is in the strip, for [inView].
  final int index;

  /// The tabs the strip's viewport shows, or null when every tab plays.
  final ValueListenable<PanelStripRange>? inView;

  @override
  Widget build(BuildContext context) {
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    Widget cover({bool inView = true}) => ContentView(
      content: content,
      scope: scope,
      preset: plays
          ? AssetPresets.keyboardCell(
              extent: size,
              devicePixelRatio: devicePixelRatio,
            )
          : AssetPreset(
              size: Size.square(size),
              spec: AssetSpec.atDensity(
                logicalWidth: size,
                logicalHeight: size,
                devicePixelRatio: devicePixelRatio,
                variant: AssetVariant.firstFrame,
              ),
              profile: const AssetProfile(),
            ),
      placeholder: standIn,
      placeholderTint: tokens.categoryIcon,
      inView: inView,
      // The panel's tickers stop while it moves or is hidden: the cover
      // holds its frame and its lease then, as the grid's cells do.
      holdsWhileTickersOff: true,
    );
    final view = SizedBox.square(
      dimension: size,
      child: switch (inView) {
        final range? => ValueListenableBuilder<PanelStripRange>(
          valueListenable: range,
          builder: (context, shown, _) => cover(inView: shown.contains(index)),
        ),
        null => cover(),
      },
    );
    return switch (radius) {
      final radius? => ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: view,
      ),
      null => view,
    };
  }
}
