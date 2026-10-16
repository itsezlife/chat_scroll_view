import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:panel_pages/src/emoji/emoji_category_strip.dart';
import 'package:panel_pages/src/emoji/emoji_strip_footer.dart';

/// The emoji strip under the touch arrangement once there are packs: the
/// reference mobile client's strip as it is with custom emoji.
///
/// ## Layout
///
/// One row, [EmojiCategoryStrip.padH] in from both ends, its tabs
/// [EmojiCategoryStrip.cell] square and [EmojiCategoryStrip.gap] apart: the
/// recents, the **group** of the categories, then a tab per pack drawn by its
/// cover. The row scrolls sideways when it does not fit.
///
/// The group folds the categories into one tab. While a category is active
/// it is open: [groupPitch] per category, as wide as all of them up to five
/// and seven tenths (it scrolls inside beyond that). Otherwise it is one tab
/// wide and shows its first category's icon; it closes back to its start.
///
/// ## The active tab
///
/// One pill marks it: a tab's circle, or the whole open group, the category in
/// it told by its icon's colour. The pill slides from tab to tab, widening at
/// the middle of its way, and the group shows only what is inside the pill or
/// its first tab's circle, so it is revealed as the pill reaches it. The row
/// scrolls to keep a pack in view and back to its start for the recents and
/// the group; an open group scrolls to keep its active category in view.
///
/// The first build, disabled animations and instant motion place everything
/// at once.
///
/// Requires the chrome theme scope. A tab chosen is reported through
/// [onChoose]; the strip's owner decides what becomes active.
class EmojiStripTabs extends StatefulWidget {
  /// A strip of [recents] (when there are any), the group of [categories] and
  /// [packs], marking [active].
  const EmojiStripTabs({
    required this.categories,
    required this.packs,
    required this.active,
    required this.onChoose,
    this.recents,
    this.assets,
    super.key,
  });

  /// The recents' tab, or null when it is not shown.
  final EmojiFooterIcon? recents;

  /// The categories, in strip order, folded into the group.
  final List<EmojiFooterIcon> categories;

  /// A tab per pack, after the group.
  final List<EmojiFooterIcon> packs;

  /// The id of the active tab, or null for none.
  final String? active;

  /// Where pack covers are drawn from; null draws none.
  final AssetCacheScope? assets;

  /// The id of a tab the user chose.
  final ValueChanged<String> onChoose;

  /// Pitch of a category inside the group: a tab and a 2 px gap.
  static const double groupPitch = EmojiCategoryStrip.cell + 2;

  /// How many categories an open group shows at most before it scrolls.
  static const double groupShownMax = 5.7;

  /// Identifies the group of the categories.
  static const Key groupKey = ValueKey<String>('emoji-strip-group');

  @override
  State<EmojiStripTabs> createState() => _EmojiStripTabsState();
}

class _EmojiStripTabsState extends State<EmojiStripTabs>
    with TickerProviderStateMixin {
  // The reference mobile client's motion: the pill 350 ms, the group 475 ms,
  // the scrolls 250 ms, all ease-out quint.
  static const Duration _selectDuration = Duration(milliseconds: 350);
  static const Duration _groupDuration = Duration(milliseconds: 475);
  static const Duration _scrollDuration = Duration(milliseconds: 250);
  static const Curve _curve = Curves.easeOutQuint;

  // How far from an edge a tab revealed by a scroll lands.
  static const double _revealMargin = 50;

  static const double _cell = EmojiCategoryStrip.cell;
  static const double _gap = EmojiCategoryStrip.gap;
  static const double _padH = EmojiCategoryStrip.padH;
  static const double _top = (EmojiCategoryStrip.height - _cell) / 2;

  late final AnimationController _select = AnimationController(
    vsync: this,
    duration: _selectDuration,
  );
  late final AnimationController _group = AnimationController(
    vsync: this,
    duration: _groupDuration,
  );
  final _row = ScrollController();
  final _inside = ScrollController();

  // The pill's position in tab indices (a fraction while it slides) and where
  // the slide started and ends.
  double _from = 0;
  double _to = 0;
  bool _placed = false;

  // How open the group is (0 closed, 1 open) where its motion started and
  // where it ends. Both motions run their controller from 0 and ease the
  // time, as the reference client's animators do from the value they are at:
  // easing the controller's value instead turns ease-out into ease-in
  // whenever it runs backwards, and the group lagged behind the pill.
  double _openFrom = 0;
  double _openTo = 0;

  double get _openNow =>
      lerpDouble(_openFrom, _openTo, _curve.transform(_group.value))!;

  // --- Geometry -------------------------------------------------------------

  bool get _hasRecents => widget.recents != null;

  int get _groupIndex => _hasRecents ? 1 : 0;

  int get _tabCount => _groupIndex + 1 + widget.packs.length;

  double get _groupOpenWidth =>
      EmojiStripTabs.groupPitch *
      math.min(EmojiStripTabs.groupShownMax, widget.categories.length);

  double _groupWidthAt(double open) =>
      lerpDouble(_cell, _groupOpenWidth, open)!;

  double _widthOf(int index, double open) =>
      index == _groupIndex ? _groupWidthAt(open) : _cell;

  Rect _boundsOf(int index, double open) {
    var x = _padH;
    for (var i = 0; i < index; i++) {
      x += _widthOf(i, open) + _gap;
    }
    return Rect.fromLTWH(x, _top, _widthOf(index, open), _cell);
  }

  double _rowWidth(double open) {
    final last = _boundsOf(_tabCount - 1, open);
    return last.right + _padH;
  }

  // The tab [id] is in, or null when no tab has it.
  int? _indexOf(String? id) {
    if (id == null) return null;
    if (widget.recents?.id == id) return 0;
    if (widget.categories.any((icon) => icon.id == id)) return _groupIndex;
    final pack = widget.packs.indexWhere((icon) => icon.id == id);
    return pack < 0 ? null : _groupIndex + 1 + pack;
  }

  // The pill now: between the tabs it slides through, widening at the middle
  // of its way and a little flatter, as the reference client draws it.
  Rect _pillAt(double open) {
    final a = _curve.transform(_select.value);
    final at = lerpDouble(_from, _to, a)!;
    final low = at.floor().clamp(0, _tabCount - 1);
    final high = at.ceil().clamp(0, _tabCount - 1);
    final rect = Rect.lerp(
      _boundsOf(low, open),
      _boundsOf(high, open),
      at - at.floor(),
    )!;
    final middle = 4 * a * (1 - a);
    return Rect.fromCenter(
      center: rect.center,
      width: rect.width * (1 + middle * .3),
      height: rect.height * (1 - middle * .05),
    );
  }

  // --- Following the active tab ---------------------------------------------

  @override
  void initState() {
    super.initState();
    _aim(animate: false);
  }

  @override
  void didUpdateWidget(EmojiStripTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    final moved =
        oldWidget.active != widget.active ||
        oldWidget.recents?.id != widget.recents?.id ||
        oldWidget.packs.length != widget.packs.length;
    if (moved) _aim(animate: _placed);
  }

  @override
  void dispose() {
    _select.dispose();
    _group.dispose();
    _row.dispose();
    _inside.dispose();
    super.dispose();
  }

  bool get _still {
    final motion = ChromeMotionScope.maybeOf(context);
    return MediaQuery.maybeDisableAnimationsOf(context) == true ||
        motion?.specOf(MotionRole.selectionSlide).duration == Duration.zero;
  }

  // Points the pill and the group at the active tab, and scrolls them to it.
  void _aim({required bool animate}) {
    final index = _indexOf(widget.active);
    if (index == null) return;
    final moving = animate && !_still;
    final open = index == _groupIndex;
    // Another category of the open group leaves the pill where it is, as the
    // reference client starts its slide only when the tab changes: a slide
    // from a tab to itself would still swell it at the middle of its way.
    final slides = !_placed || index.toDouble() != _to;
    if (slides) {
      final now = lerpDouble(_from, _to, _curve.transform(_select.value))!;
      _from = moving ? now : index.toDouble();
      _to = index.toDouble();
      final openNow = _openNow;
      _openFrom = moving ? openNow : (open ? 1 : 0);
      _openTo = open ? 1 : 0;
      if (moving) {
        unawaited(_select.forward(from: 0));
        // The whole 475 ms from wherever it is, as the reference client
        // restarts it.
        unawaited(_group.forward(from: 0));
      } else {
        _select.value = 1;
        _group.value = 1;
      }
    }
    _placed = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _revealRow(index, open: open, animate: moving);
      _revealInside(animate: moving);
    });
  }

  // A pack is kept in view; the recents and the group bring the row back to
  // its start.
  void _revealRow(int index, {required bool open, required bool animate}) {
    if (!_row.hasClients) return;
    final position = _row.position;
    double? to;
    if (index <= _groupIndex) {
      to = 0;
    } else {
      final bounds = _boundsOf(index, open ? 1 : 0);
      to = _revealTarget(
        bounds.left,
        bounds.right,
        position.pixels,
        position.viewportDimension,
      );
    }
    if (to == null) return;
    _scroll(_row, to.clamp(0, position.maxScrollExtent), animate: animate);
  }

  // An open group keeps its active category in view; a closed one goes back
  // to its start.
  void _revealInside({required bool animate}) {
    if (!_inside.hasClients) return;
    final position = _inside.position;
    final category = widget.categories.indexWhere(
      (icon) => icon.id == widget.active,
    );
    if (category < 0) {
      _scroll(_inside, 0, animate: animate);
      return;
    }
    final left = category * EmojiStripTabs.groupPitch;
    final to = _revealTarget(
      left,
      left + _cell,
      position.pixels,
      _groupOpenWidth,
    );
    if (to == null) return;
    final max = math.max<double>(
      0,
      widget.categories.length * EmojiStripTabs.groupPitch - _groupOpenWidth,
    );
    _scroll(_inside, to.clamp(0, max), animate: animate);
  }

  // Where to scroll so [left]..[right] is at least [_revealMargin] in from
  // either edge of a [view] wide window at [offset], or null where it is.
  static double? _revealTarget(
    double left,
    double right,
    double offset,
    double view,
  ) {
    if (left < offset + _revealMargin) return left - _revealMargin;
    if (right > offset + view - _revealMargin) {
      return right - view + _revealMargin;
    }
    return null;
  }

  void _scroll(
    ScrollController controller,
    double to, {
    required bool animate,
  }) {
    if ((controller.offset - to).abs() < .5) return;
    if (animate) {
      unawaited(
        controller.animateTo(to, duration: _scrollDuration, curve: _curve),
      );
    } else {
      controller.jumpTo(to);
    }
  }

  // --- Build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final tokens = ChromeThemeScope.panelOf(context);
    final colorDuration = _still ? Duration.zero : _selectDuration;
    Widget tab(EmojiFooterIcon icon) => _Tab(
      icon: icon,
      selected: icon.id == widget.active,
      tokens: tokens,
      assets: widget.assets,
      duration: colorDuration,
      onTap: () => widget.onChoose(icon.id),
    );

    return SingleChildScrollView(
      controller: _row,
      scrollDirection: Axis.horizontal,
      child: AnimatedBuilder(
        animation: Listenable.merge([_select, _group]),
        builder: (context, _) {
          final open = _openNow;
          final pill = _pillAt(open);
          final group = _boundsOf(_groupIndex, open);
          return CustomPaint(
            painter: _PillPainter(
              pill: pill,
              // The idle icon colour at a low alpha: the wash is a tint of
              // the icon, as the touch strip's has always been.
              color: tokens.categoryIcon.withValues(
                alpha: tokens.categoryIcon.a * 0.18,
              ),
            ),
            child: SizedBox(
              width: _rowWidth(open),
              height: EmojiCategoryStrip.height,
              child: Stack(
                children: [
                  if (widget.recents case final recents?)
                    Positioned.fromRect(
                      rect: _boundsOf(0, open),
                      child: tab(recents),
                    ),
                  Positioned.fromRect(
                    rect: group,
                    child: ClipPath(
                      key: EmojiStripTabs.groupKey,
                      clipper: _GroupClip(pill: pill.shift(-group.topLeft)),
                      child: SingleChildScrollView(
                        controller: _inside,
                        scrollDirection: Axis.horizontal,
                        physics: open >= 1
                            ? null
                            : const NeverScrollableScrollPhysics(),
                        child: Row(
                          children: [
                            for (final (i, icon)
                                in widget.categories.indexed) ...[
                              if (i > 0)
                                const SizedBox(
                                  width: EmojiStripTabs.groupPitch - _cell,
                                ),
                              SizedBox.square(
                                dimension: _cell,
                                child: tab(icon),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  for (final (i, pack) in widget.packs.indexed)
                    Positioned.fromRect(
                      rect: _boundsOf(_groupIndex + 1 + i, open),
                      child: tab(pack),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// What the group shows: what is inside the pill, and its first tab's circle.
final class _GroupClip extends CustomClipper<Path> {
  const _GroupClip({required this.pill});

  /// The pill, in the group's coordinates.
  final Rect pill;

  @override
  Path getClip(Size size) => Path()
    ..addRRect(RRect.fromRectAndRadius(pill, Radius.circular(pill.height / 2)))
    ..addOval(
      Rect.fromCircle(
        center: Offset(EmojiCategoryStrip.cell / 2, size.height / 2),
        radius: EmojiCategoryStrip.cell / 2,
      ),
    );

  @override
  bool shouldReclip(_GroupClip oldClipper) => oldClipper.pill != pill;
}

final class _PillPainter extends CustomPainter {
  const _PillPainter({required this.pill, required this.color});

  final Rect pill;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) => canvas.drawRRect(
    RRect.fromRectAndRadius(pill, Radius.circular(pill.height / 2)),
    Paint()..color = color,
  );

  @override
  bool shouldRepaint(_PillPainter oldDelegate) =>
      oldDelegate.pill != pill || oldDelegate.color != color;
}

/// One tab: a chrome icon in the idle or selected colour, or a pack's cover.
class _Tab extends StatelessWidget {
  const _Tab({
    required this.icon,
    required this.selected,
    required this.tokens,
    required this.assets,
    required this.duration,
    required this.onTap,
  });

  final EmojiFooterIcon icon;
  final bool selected;
  final PanelTokens tokens;
  final AssetCacheScope? assets;
  final Duration duration;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: icon.label,
    onTap: onTap,
    child: ExcludeSemantics(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Center(
          child: switch ((icon.icon, icon.cover, assets)) {
            (final chrome?, _, _) => TweenAnimationBuilder<double>(
              tween: Tween<double>(end: selected ? 1 : 0),
              duration: duration,
              curve: Curves.easeOutQuint,
              builder: (context, t, _) => ChromeIcon(
                chrome,
                size: EmojiCategoryStrip.iconSize,
                color: Color.lerp(
                  tokens.categoryIcon,
                  tokens.categoryIconSelected,
                  t,
                ),
              ),
            ),
            // The cover's first frame, as a still of its own: the reference
            // client's tab is static, and a still entry holds no decoder.
            (null, final cover?, final scope?) => SizedBox.square(
              dimension: EmojiCategoryStrip.iconSize,
              child: ContentView(
                content: cover,
                scope: scope,
                preset: AssetPreset(
                  size: const Size.square(EmojiCategoryStrip.iconSize),
                  spec: AssetSpec.atDensity(
                    logicalWidth: EmojiCategoryStrip.iconSize,
                    logicalHeight: EmojiCategoryStrip.iconSize,
                    devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
                    variant: AssetVariant.firstFrame,
                  ),
                  profile: const AssetProfile(),
                ),
              ),
            ),
            _ => const SizedBox.shrink(),
          },
        ),
      ),
    ),
  );
}
