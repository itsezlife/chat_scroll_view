import 'dart:math' as math;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/foundation.dart' show clampDouble;
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:panel_pages/src/emoji/emoji_category_strip.dart'
    show EmojiStripLayout;

/// One icon of the [EmojiStripFooter]: a chrome icon (the recents, a
/// category) or a piece of content (a pack's cover).
@immutable
final class EmojiFooterIcon {
  /// An icon named [id], announced as [label].
  const EmojiFooterIcon({
    required this.id,
    required this.label,
    this.icon,
    this.cover,
  });

  /// What the footer reports when the icon is chosen, and matches against
  /// the active id.
  final String id;

  /// What assistive technology announces.
  final String label;

  /// The chrome icon drawn, for the recents and the categories.
  final ChromeIconId? icon;

  /// The content drawn, for a pack; null draws nothing in the slot.
  final ContentKey? cover;
}

/// The emoji strip under the pointer arrangement: the reference desktop
/// client's footer as it is with packs of its own.
///
/// ## Layout
///
/// [height] px tall on the strip fill, no line over it. Every icon has a
/// [slot] px slot, from [inset] px in, left-aligned: the recents, then the
/// categories folded into one icon (the first category's), then a slot per
/// pack. While a category is active the folded icon opens, linearly over
/// [groupSlide], into a group of the categories' icons, as wide as the footer
/// leaves it (at most every icon, at least five and a half; a narrower group
/// scrolls its icons).
///
/// ## The active icon
///
/// A [markerSize] square of radius 8 under the active recents or pack; a pill
/// of radius 14 over the whole open group while a category is active, the
/// category itself told by its icon's colour, which changes at once. The
/// marker slides over the `selectionSlide` role (400 ms, ease-out cubic) as
/// the catalogue moves into another section; a click puts it in place at
/// once. The footer (and the group) scroll, linearly over the same 400 ms, to
/// centre the active icon. The first selection, a change of width, disabled
/// animations and instant motion place everything at once.
///
/// ## Scrolling
///
/// When the icons overflow, the wheel (horizontal delta first) and a mouse
/// drag scroll the footer, or the open group under the pointer, at once,
/// with no fling. An edge with icons beyond it fades into the fill over
/// [fadeExtent] px. A click that dragged picks nothing.
class EmojiStripFooter extends StatefulWidget {
  /// A footer over [recents], [categories] and [packs], [active] marked.
  const EmojiStripFooter({
    required this.recents,
    required this.categories,
    required this.packs,
    required this.active,
    required this.onChoose,
    this.assets,
    this.layout = EmojiStripLayout.automatic,
    super.key,
  });

  /// Plain or grouped; see [EmojiStripLayout].
  final EmojiStripLayout layout;

  /// The recents icon, or null when the page shows no recents.
  final EmojiFooterIcon? recents;

  /// The categories, in order.
  final List<EmojiFooterIcon> categories;

  /// The packs, in order.
  final List<EmojiFooterIcon> packs;

  /// The id of the active icon, or null for none.
  final String? active;

  /// Called with the id of the icon a click chose.
  final ValueChanged<String> onChoose;

  /// Where pack covers are drawn from; null draws no covers.
  final AssetCacheScope? assets;

  /// Height of the footer.
  static const double height = 36;

  /// Width of every icon's slot.
  static const double slot = 30;

  /// Room at each end of the footer.
  static const double inset = 3;

  /// Side of a chrome icon.
  static const double iconSize = 24;

  /// Side of a pack's cover.
  static const double coverSize = 21;

  /// Side of the marker square.
  static const double markerSize = 28;

  /// Width of the fade at an edge with icons beyond it.
  static const double fadeExtent = 24;

  /// How far a mouse moves before a press is a drag.
  static const double dragDistance = 10;

  /// How long the group takes to open or close, linearly (the reference
  /// client's slide duration).
  static const Duration groupSlide = Duration(milliseconds: 240);

  /// Identifies the marker.
  static const Key markerKey = ValueKey<String>('emoji-strip-highlight');

  @override
  State<EmojiStripFooter> createState() => _EmojiStripFooterState();
}

// A value that moves from one number to another as its controller runs.
final class _Moving {
  double from = 0;
  double to = 0;

  double at(double t) => from + (to - from) * t;

  void place(double value) => from = to = value;
}

class _EmojiStripFooterState extends State<EmojiStripFooter>
    with TickerProviderStateMixin {
  late final AnimationController _move = AnimationController(vsync: this)
    ..addListener(_repaint);
  late final AnimationController _open = AnimationController(vsync: this)
    ..addListener(_repaint);
  final _x = _Moving();
  final _subX = _Moving();
  final _selLeft = _Moving();
  final _selWidth = _Moving();
  final _groupOpen = _Moving();
  // The reference client's ease-out cubic, exactly 1 - (1 - t)^3 (Flutter's
  // `Curves.easeOutCubic` is a Bezier near it).
  static const Curve _selCurve = _CubicOut();
  double _width = 0;
  bool _placed = false;
  // The press of a mouse, until it is a drag or lifts.
  Offset? _down;
  double _dragFrom = 0;
  bool _dragGroup = false;
  bool _dragging = false;

  void _repaint() => setState(() {});

  @override
  void didUpdateWidget(EmojiStripFooter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_width <= 0) return;
    if (oldWidget.active != widget.active ||
        oldWidget.packs.length != widget.packs.length ||
        oldWidget.categories.length != widget.categories.length ||
        (oldWidget.recents == null) != (widget.recents == null)) {
      _aim(animate: _placed && oldWidget.active != null);
    }
  }

  @override
  void dispose() {
    _move.dispose();
    _open.dispose();
    super.dispose();
  }

  // --- Geometry -------------------------------------------------------------

  static const double _slot = EmojiStripFooter.slot;
  static const double _inset = EmojiStripFooter.inset;

  // The plain footer: every icon in a slot of its own, nothing folded.
  bool get _plain => switch (widget.layout) {
    EmojiStripLayout.plain => true,
    EmojiStripLayout.grouped => false,
    EmojiStripLayout.automatic => widget.packs.isEmpty,
  };

  List<EmojiFooterIcon> get _plainIcons => [
    ?widget.recents,
    ...widget.categories,
    ...widget.packs,
  ];

  // A plain slot is a grouped one: the footer's look, nothing folded.
  double get _plainSlot => _slot;

  // The slot of the layout in use: the marker sits in its middle.
  double get _slotWidth => _plain ? _plainSlot : _slot;

  double get _groupLeft => widget.recents == null ? 0 : _slot;

  // Every category's icon side by side.
  double get _groupFull => widget.categories.length * _slot;

  // The open group's width: what the footer leaves it, between five and a half
  // icons and all of them, in whole icons plus a half.
  double get _groupWidth {
    if (widget.categories.isEmpty) return 0;
    const half = _slot / 2;
    final count = (widget.recents == null ? 0 : 1) + 1 + widget.packs.length;
    final full = _groupFull;
    final least = math.min(full, 5 * _slot + half);
    var width = clampDouble(_width + _slot - count * _slot, least, full);
    if (width < full) {
      width = half + ((width - half) / _slot).floor() * _slot;
    }
    return width;
  }

  double _groupWidthAt(double open) =>
      widget.categories.isEmpty ? 0 : _slot + (_groupWidth - _slot) * open;

  double _contentWidth(double open) => _plain
      ? 2 * _inset + _plainIcons.length * _plainSlot
      : _inset +
            _groupLeft +
            _groupWidthAt(open) +
            widget.packs.length * _slot +
            _inset;

  double _maxX(double open) => math.max(0, _contentWidth(open) - _width);

  double get _maxSubX => math.max(0, _groupFull - _groupWidth);

  bool get _activeIsCategory =>
      !_plain && widget.categories.any((icon) => icon.id == widget.active);

  // Where the active icon is (from the first slot) and how wide.
  (double, double)? _selectionOf(String? id) {
    if (id == null) return null;
    if (_plain) {
      final at = _plainIcons.indexWhere((icon) => icon.id == id);
      return at < 0 ? null : (at * _plainSlot, _plainSlot);
    }
    if (widget.recents?.id == id) return (0, _slot);
    if (widget.categories.any((icon) => icon.id == id)) {
      return (_groupLeft, _groupWidth);
    }
    final pack = widget.packs.indexWhere((icon) => icon.id == id);
    if (pack < 0) return null;
    return (_groupLeft + _groupWidthAt(0) + pack * _slot, _slot);
  }

  // Points every value at the active icon: moving there when [animate],
  // placed otherwise.
  void _aim({required bool animate}) {
    final motion = ChromeMotionScope.of(context);
    final slide = motion.specOf(MotionRole.selectionSlide);
    final still =
        MediaQuery.disableAnimationsOf(context) ||
        slide.duration == Duration.zero;
    final moving = animate && !still;
    final open = _activeIsCategory ? 1.0 : 0.0;
    final selection = _selectionOf(widget.active);
    final t = Curves.linear.transform(_move.value);
    final selT = _selCurve.transform(_move.value);
    double xNow() => _x.at(t);

    if (moving) {
      _x.from = xNow();
      _subX.from = _subX.at(t);
      _selLeft.from = _selLeft.at(selT);
      _selWidth.from = _selWidth.at(selT);
      _groupOpen.from = _groupOpen.at(_open.value);
    }
    if (selection case (final left, final width)) {
      _x.to = clampDouble(
        (_inset + 2 * left + width + _inset - _width) / 2,
        0,
        _maxX(open),
      );
      _selLeft.to = left;
      _selWidth.to = width;
    } else {
      _x.to = clampDouble(_x.at(t), 0, _maxX(open));
    }
    final category = widget.categories.indexWhere(
      (icon) => icon.id == widget.active,
    );
    if (category >= 0 && !_plain) {
      _subX.to = clampDouble(
        (2 * category * _slot + _slot - _groupWidth) / 2,
        0,
        _maxSubX,
      );
    }
    _groupOpen.to = open;
    if (!moving) {
      // A placed value is the same at any point of the controllers, so they
      // are only stopped, which notifies no one (this runs during builds).
      _x.place(_x.to);
      _subX.place(_subX.to);
      _selLeft.place(_selLeft.to);
      _selWidth.place(_selWidth.to);
      _groupOpen.place(open);
      _move.stop();
      _open.stop();
      return;
    }
    _move
      ..duration = slide.duration
      ..forward(from: 0);
    _open
      ..duration = EmojiStripFooter.groupSlide
      ..forward(from: 0);
  }

  // --- Input ----------------------------------------------------------------

  void _choose(String id) {
    if (_dragging) return;
    // A click puts the marker in place; the footer still scrolls to it.
    final selection = _selectionOf(id);
    if (selection case (final left, final width)) {
      _selLeft.place(left);
      _selWidth.place(width);
    }
    widget.onChoose(id);
  }

  bool _overGroup(double dx) {
    final open = _groupOpen.at(_open.value);
    if (_plain || open <= 0) return false;
    final left = _inset + _groupLeft - _x.at(_move.value);
    return dx >= left && dx < left + _groupWidthAt(open);
  }

  void _onSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (event) {
      final scroll = event as PointerScrollEvent;
      final delta = scroll.scrollDelta.dx != 0
          ? scroll.scrollDelta.dx
          : scroll.scrollDelta.dy;
      _scrollBy(delta, group: _overGroup(scroll.localPosition.dx));
    });
  }

  void _scrollBy(double delta, {required bool group}) {
    setState(() {
      if (group && _maxSubX > 0) {
        _subX.place(clampDouble(_subX.at(_move.value) + delta, 0, _maxSubX));
      } else {
        _x.place(
          clampDouble(
            _x.at(_move.value) + delta,
            0,
            _maxX(_groupOpen.at(_open.value)),
          ),
        );
      }
    });
  }

  void _onDown(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.mouse) return;
    _down = event.localPosition;
    _dragGroup = _overGroup(event.localPosition.dx) && _maxSubX > 0;
    _dragFrom = _dragGroup ? _subX.at(_move.value) : _x.at(_move.value);
    _dragging = false;
  }

  void _onMove(PointerMoveEvent event) {
    final down = _down;
    if (down == null) return;
    final moved = event.localPosition - down;
    if (!_dragging &&
        moved.dx.abs() + moved.dy.abs() < EmojiStripFooter.dragDistance) {
      return;
    }
    _dragging = true;
    final value = _dragFrom - moved.dx;
    setState(() {
      if (_dragGroup) {
        _subX.place(clampDouble(value, 0, _maxSubX));
      } else {
        _x.place(clampDouble(value, 0, _maxX(_groupOpen.at(_open.value))));
      }
    });
  }

  void _onUp(PointerEvent event) {
    _down = null;
    // The tap of this press, if any, is heard before the next one.
    WidgetsBinding.instance.addPostFrameCallback((_) => _dragging = false);
  }

  // --- Build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final panel = ChromeThemeScope.panelOf(context);
    return ColoredBox(
      color: panel.stripFill,
      child: SizedBox(
        height: EmojiStripFooter.height,
        width: double.infinity,
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth != _width) {
              _width = constraints.maxWidth;
              // A new width places everything again, as the reference
              // client's geometry refresh does.
              _aim(animate: false);
              _placed = widget.active != null;
            } else if (!_placed && widget.active != null) {
              _aim(animate: false);
              _placed = true;
            }
            return Listener(
              onPointerSignal: _onSignal,
              onPointerDown: _onDown,
              onPointerMove: _onMove,
              onPointerUp: _onUp,
              onPointerCancel: _onUp,
              child: _paint(panel),
            );
          },
        ),
      ),
    );
  }

  Widget _paint(PanelTokens panel) {
    final t = _move.value;
    final x = _x.at(t);
    final selT = _selCurve.transform(t);
    final open = _groupOpen.at(_open.value);
    final groupWidth = _groupWidthAt(open);
    // Everything below is placed from the first slot and clipped to the
    // footer less its insets.
    final groupLeft = _groupLeft - x;
    final selection = _selectionOf(widget.active);
    final maxX = _maxX(open);

    final slotWidth = _slotWidth;
    Widget icon(EmojiFooterIcon icon, double left) => Positioned(
      left: left,
      top: 0,
      width: slotWidth,
      height: EmojiStripFooter.height,
      child: _FooterButton(
        icon: icon,
        selected: icon.id == widget.active,
        tokens: panel,
        assets: widget.assets,
        onTap: () => _choose(icon.id),
      ),
    );

    // Over an opening group the marker grows towards the group's width as it
    // is now, not as it will be, so it never reaches past the group.
    final selWidth = _activeIsCategory
        ? _selWidth.from + (groupWidth - _selWidth.from) * selT
        : _selWidth.at(selT);
    final pill = math.max<double>(1, _groupWidth - _slot);
    final round = _plain ? 0.0 : clampDouble((selWidth - _slot) / pill, 0, 1);
    // The marker is the slot less this on each side: a 28 px square in a
    // single slot, the open group less as much in a pill.
    final markerInset = ((slotWidth - EmojiStripFooter.markerSize) / 2)
        .floorToDouble();
    final first = widget.categories.firstOrNull;
    // The open group's icons are clipped 3 px in from its ends.
    const groupInset = 3.0;
    return Stack(
      children: [
        Positioned.fill(
          left: _inset,
          right: _inset,
          child: ClipRect(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                if (selection != null)
                  Positioned(
                    key: EmojiStripFooter.markerKey,
                    left: _selLeft.at(selT) - x + markerInset,
                    top:
                        (EmojiStripFooter.height -
                            EmojiStripFooter.markerSize) /
                        2,
                    width: selWidth - 2 * markerInset,
                    height: EmojiStripFooter.markerSize,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: panel.tabSelector,
                        borderRadius: BorderRadius.circular(8 + 6 * round),
                      ),
                    ),
                  ),
                if (_plain)
                  for (final (i, each) in _plainIcons.indexed)
                    icon(each, i * slotWidth - x)
                else ...[
                  if (widget.recents case final recents?) icon(recents, -x),
                  if (first != null && open <= 0)
                    icon(first, groupLeft)
                  else if (first != null)
                    Positioned(
                      left: groupLeft + groupInset,
                      top: 0,
                      width: math.max(0, groupWidth - 2 * groupInset),
                      height: EmojiStripFooter.height,
                      child: ClipRect(
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            for (var i = 0; i < widget.categories.length; i++)
                              icon(
                                widget.categories[i],
                                i * _slot - _subX.at(t) - groupInset,
                              ),
                          ],
                        ),
                      ),
                    ),
                  for (var i = 0; i < widget.packs.length; i++)
                    icon(widget.packs[i], groupLeft + groupWidth + i * _slot),
                ],
              ],
            ),
          ),
        ),
        if (x > 0)
          _fade(panel, start: true, opacity: x / EmojiStripFooter.fadeExtent),
        if (x < maxX)
          _fade(
            panel,
            start: false,
            opacity: (maxX - x) / EmojiStripFooter.fadeExtent,
          ),
      ],
    );
  }

  Widget _fade(
    PanelTokens panel, {
    required bool start,
    required double opacity,
  }) => Positioned(
    left: start ? _inset : null,
    right: start ? null : _inset,
    top: 0,
    width: EmojiStripFooter.fadeExtent,
    height: EmojiStripFooter.height,
    child: IgnorePointer(
      child: Opacity(
        opacity: clampDouble(opacity, 0, 1),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: start ? Alignment.centerLeft : Alignment.centerRight,
              end: start ? Alignment.centerRight : Alignment.centerLeft,
              colors: [panel.stripFill, panel.stripFill.withValues(alpha: 0)],
            ),
          ),
        ),
      ),
    ),
  );
}

class _FooterButton extends StatelessWidget {
  const _FooterButton({
    required this.icon,
    required this.selected,
    required this.tokens,
    required this.assets,
    required this.onTap,
  });

  final EmojiFooterIcon icon;
  final bool selected;
  final PanelTokens tokens;
  final AssetCacheScope? assets;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final chrome = icon.icon;
    final cover = icon.cover;
    final scope = assets;
    return Semantics(
      button: true,
      selected: selected,
      label: icon.label,
      onTap: onTap,
      child: ExcludeSemantics(
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Center(
              child: switch ((chrome, cover, scope)) {
                (final chrome?, _, _) => ChromeIcon(
                  chrome,
                  size: EmojiStripFooter.iconSize,
                  color: selected
                      ? tokens.categoryIconSelected
                      : tokens.categoryIcon,
                ),
                (null, final cover?, final scope?) => SizedBox.square(
                  dimension: EmojiStripFooter.coverSize,
                  child: ContentView(
                    content: cover,
                    scope: scope,
                    preset: AssetPresets.keyboardCell(
                      extent: EmojiStripFooter.coverSize,
                      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
                    ),
                  ),
                ),
                _ => const SizedBox.shrink(),
              },
            ),
          ),
        ),
      ),
    );
  }
}

// 1 - (1 - t)^3.
final class _CubicOut extends Curve {
  const _CubicOut();

  @override
  double transformInternal(double t) {
    final rest = 1 - t;
    return 1 - rest * rest * rest;
  }
}
