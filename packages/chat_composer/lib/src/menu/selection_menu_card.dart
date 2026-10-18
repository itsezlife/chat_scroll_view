import 'dart:math' as math;

import 'package:chat_composer/src/menu/selection_menu_items.dart';
import 'package:chat_composer/src/menu/selection_menu_layout.dart';
import 'package:chat_composer/src/menu/selection_menu_metrics.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/material.dart';

/// The selection menu's card: the main row, the More button, and the overflow
/// page that the card reshapes itself into.
///
/// The card owns the morph and nothing else. Where it sits, what it holds and
/// when it is visible are the caller's: the caller gives it a [placement],
/// the items already split between the row and the page, and an [opacity] it
/// fades with. It is a positioned child of the overlay's [Stack].
///
/// **The morph.** Opening the page does not slide, scale or dim anything: the
/// card's width and height change toward the page's size on different curves,
/// the row fades out, the page is there at once, and the More button becomes
/// the back row. Every piece keeps to the card's end edge (and its bottom edge
/// when the page opens upwards), so the page appears to unfold from the row.
/// Closing runs it backwards with the curves swapped. Pointers are absorbed
/// while it runs.
class SelectionMenuCard extends StatefulWidget {
  /// A card for [placement] holding [mainItems] and [overflowItems].
  const SelectionMenuCard({
    required this.placement,
    required this.mainItems,
    required this.mainWidths,
    required this.overflowItems,
    required this.itemStyle,
    required this.tokens,
    required this.strings,
    required this.motion,
    required this.opacity,
    required this.onSelected,
    super.key,
  });

  /// Where the card sits and the sizes of its two pages.
  final SelectionMenuPlacement placement;

  /// The items on the main row, in order.
  final List<SelectionMenuItem> mainItems;

  /// The width of each of [mainItems].
  final List<double> mainWidths;

  /// The items on the overflow page, in order. Empty when there is no page and
  /// no More button.
  final List<SelectionMenuItem> overflowItems;

  /// The text style of the items; the back row's label overrides its size.
  final TextStyle itemStyle;

  /// The card's colours.
  final SelectionMenuTokens tokens;

  /// The More and Back labels.
  final FormattingStrings strings;

  /// The roles and speed of the morph.
  final ChromeMotionData motion;

  /// How visible the whole card is.
  final Animation<double> opacity;

  /// Called when an item is chosen.
  final ValueChanged<SelectionMenuItem> onSelected;

  @override
  State<SelectionMenuCard> createState() => SelectionMenuCardState();
}

/// The state of [SelectionMenuCard]; exposes whether the overflow page is open
/// so the menu can keep it across a hide and a show.
class SelectionMenuCardState extends State<SelectionMenuCard>
    with TickerProviderStateMixin {
  late final AnimationController _morph = AnimationController(vsync: this);
  late final AnimationController _mainAlpha = AnimationController(
    vsync: this,
    value: 1,
  );
  late final AnimationController _listAlpha = AnimationController(vsync: this);

  var _open = false;
  var _opening = true;

  /// Whether the overflow page is open, or opening.
  bool get isOpen => _open;

  /// Whether the card is between the row and the page.
  bool get isAnimating => _morph.isAnimating;

  @override
  void dispose() {
    _morph.dispose();
    _mainAlpha.dispose();
    _listAlpha.dispose();
    super.dispose();
  }

  SelectionMenuMorph get _geometry => SelectionMenuMorph(
    main: widget.placement.main,
    overflow: widget.placement.overflow ?? widget.placement.main,
    upwards: widget.placement.overflowUpwards,
    rtl: widget.placement.rtl,
  );

  /// Opens the overflow page.
  void open() => _run(opening: true);

  /// Returns to the main row.
  void close() => _run(opening: false);

  void _run({required bool opening}) {
    if (widget.placement.overflow == null ||
        _open == opening ||
        _morph.isAnimating) {
      return;
    }
    final motion = widget.motion;
    setState(() {
      _open = opening;
      _opening = opening;
    });
    final base = motion.durationOf(MotionRole.menuSizeEase);
    _morph
      ..value = 0
      ..animateTo(
        1,
        duration: SelectionMenuTiming.morphDuration(
          base,
          diagonal: _geometry.diagonal,
        ),
        curve: Curves.linear,
      );
    if (opening) {
      _listAlpha.value = 1;
      _mainAlpha.animateTo(
        0,
        duration: motion.durationOf(MotionRole.menuMainFadeOut),
        curve: motion.curveOf(MotionRole.menuMainFadeOut),
      );
    } else {
      _mainAlpha.animateTo(
        1,
        duration: motion.durationOf(MotionRole.menuMainFadeIn),
        curve: motion.curveOf(MotionRole.menuMainFadeIn),
      );
      _listAlpha.animateTo(
        0,
        duration: motion.durationOf(MotionRole.menuOverflowFadeOut),
        curve: motion.curveOf(MotionRole.menuOverflowFadeOut),
      );
    }
  }

  SelectionMenuFrame _frame() {
    final motion = widget.motion;
    final t = _morph.value;
    final ease = motion.curveOf(MotionRole.menuSizeEase).transform(t);
    final accelerate = motion
        .curveOf(MotionRole.menuSizeAccelerate)
        .transform(t);
    // A card at rest has no morph running: the value says which page it rests
    // on.
    if (!_morph.isAnimating && _morph.value == 0) {
      return _geometry.frame(
        opening: true,
        width: _open ? 1 : 0,
        height: _open ? 1 : 0,
        ease: _open ? 1 : 0,
      );
    }
    return _geometry.frame(
      opening: _opening,
      width: _opening ? accelerate : ease,
      height: _opening ? ease : accelerate,
      ease: ease,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = widget.tokens;
    final listenable = Listenable.merge([_morph, _mainAlpha, _listAlpha]);
    return AnimatedBuilder(
      animation: listenable,
      builder: (context, _) {
        final frame = _frame();
        final rect = widget.placement.cardRect(frame.size);
        return Positioned.fromRect(
          rect: rect,
          child: FadeTransition(
            opacity: widget.opacity,
            child: AbsorbPointer(
              absorbing: _morph.isAnimating,
              child: Material(
                elevation: SelectionMenuTokens.elevation,
                color: tokens.background,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(
                    Radius.circular(SelectionMenuTokens.cornerRadius),
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: FocusTraversalGroup(
                  policy: ReadingOrderTraversalPolicy(),
                  child: Stack(
                    children: [
                      // A page and a row at rest out of sight are not built, so
                      // they are neither hit nor spoken.
                      if (widget.overflowItems.isNotEmpty &&
                          (_open || _listAlpha.value > 0))
                        Positioned.fromRect(
                          key: const ValueKey<String>('overflow'),
                          rect: frame.list,
                          child: IgnorePointer(
                            ignoring: !_open,
                            child: FadeTransition(
                              opacity: _listAlpha,
                              child: _OverflowList(
                                items: widget.overflowItems,
                                style: widget.itemStyle,
                                tokens: tokens,
                                onSelected: widget.onSelected,
                              ),
                            ),
                          ),
                        ),
                      if (!_open || _mainAlpha.value > 0)
                        Positioned.fromRect(
                          key: const ValueKey<String>('main'),
                          rect: frame.main,
                          child: IgnorePointer(
                            ignoring: _open,
                            child: FadeTransition(
                              opacity: _mainAlpha,
                              child: _MainRow(
                                items: widget.mainItems,
                                widths: widget.mainWidths,
                                trailing: widget.overflowItems.isNotEmpty
                                    ? SelectionMenuMetrics.moreWidth
                                    : 0,
                                style: widget.itemStyle,
                                tokens: tokens,
                                onSelected: widget.onSelected,
                              ),
                            ),
                          ),
                        ),
                      if (widget.overflowItems.isNotEmpty)
                        Positioned.fromRect(
                          key: const ValueKey<String>('back'),
                          rect: frame.backRow,
                          child: _BackRow(
                            progress: frame.backOpacity,
                            open: _open,
                            style: widget.itemStyle,
                            tokens: tokens,
                            strings: widget.strings,
                            onPressed: _open ? close : open,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// --- Item label ---

/// [base] set the way an item's [style] shows its own effect; also what an item
/// is measured with, so the row splits where it would draw.
TextStyle selectionMenuLabelStyle(
  TextStyle base,
  SelectionMenuLabelStyle style,
) => switch (style) {
  SelectionMenuLabelStyle.plain => base,
  SelectionMenuLabelStyle.italic => base.copyWith(fontStyle: FontStyle.italic),
  SelectionMenuLabelStyle.mono => base.copyWith(fontFamily: 'monospace'),
  SelectionMenuLabelStyle.strike => base.copyWith(
    decoration: TextDecoration.lineThrough,
  ),
  SelectionMenuLabelStyle.underline => base.copyWith(
    decoration: TextDecoration.underline,
  ),
};

class _ItemButton extends StatelessWidget {
  const _ItemButton({
    required this.item,
    required this.child,
    required this.tokens,
    required this.onSelected,
  });

  final SelectionMenuItem item;
  final Widget child;
  final SelectionMenuTokens tokens;
  final ValueChanged<SelectionMenuItem> onSelected;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: item.selected,
    label: item.label,
    excludeSemantics: true,
    onTap: () => onSelected(item),
    child: InkWell(
      key: ValueKey<SelectionMenuItemKind>(item.kind),
      onTap: () => onSelected(item),
      splashFactory: InkRipple.splashFactory,
      splashColor: tokens.pressHighlight,
      highlightColor: tokens.pressHighlight,
      hoverColor: tokens.pressHighlight,
      focusColor: tokens.pressHighlight,
      child: child,
    ),
  );
}

// --- Main row ---

class _MainRow extends StatelessWidget {
  const _MainRow({
    required this.items,
    required this.widths,
    required this.trailing,
    required this.style,
    required this.tokens,
    required this.onSelected,
  });

  final List<SelectionMenuItem> items;
  final List<double> widths;
  final double trailing;
  final TextStyle style;
  final SelectionMenuTokens tokens;
  final ValueChanged<SelectionMenuItem> onSelected;

  @override
  Widget build(BuildContext context) {
    final last = items.length - 1;
    return Padding(
      padding: EdgeInsetsDirectional.only(end: trailing),
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++)
            SizedBox(
              width: widths[i],
              height: SelectionMenuMetrics.rowHeight,
              child: _ItemButton(
                item: items[i],
                tokens: tokens,
                onSelected: onSelected,
                child: Padding(
                  padding: EdgeInsetsDirectional.only(
                    start: i == 0
                        ? SelectionMenuMetrics.outerItemPadding
                        : SelectionMenuMetrics.itemPadding,
                    // The last item of the whole list sits at the row's end
                    // only when nothing overflows; the More button's room
                    // follows an item that is not last.
                    end: i == last && trailing == 0
                        ? SelectionMenuMetrics.outerItemPadding
                        : SelectionMenuMetrics.itemPadding,
                  ),
                  child: Center(
                    child: Text(
                      items[i].label,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: selectionMenuLabelStyle(
                        style,
                        items[i].labelStyle,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// --- Overflow page ---

class _OverflowList extends StatelessWidget {
  const _OverflowList({
    required this.items,
    required this.style,
    required this.tokens,
    required this.onSelected,
  });

  final List<SelectionMenuItem> items;
  final TextStyle style;
  final SelectionMenuTokens tokens;
  final ValueChanged<SelectionMenuItem> onSelected;

  static const double _contentExtent =
      SelectionMenuMetrics.overflowListPaddingTop +
      SelectionMenuMetrics.overflowListPaddingBottom;

  @override
  Widget build(BuildContext context) {
    final list = ListView.builder(
      primary: false,
      padding: const EdgeInsets.only(
        top: SelectionMenuMetrics.overflowListPaddingTop,
        bottom: SelectionMenuMetrics.overflowListPaddingBottom,
      ),
      itemCount: items.length,
      itemExtent: SelectionMenuMetrics.overflowRowHeight,
      itemBuilder: (context, index) {
        final item = items[index];
        return _ItemButton(
          item: item,
          tokens: tokens,
          onSelected: onSelected,
          child: Padding(
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: SelectionMenuMetrics.overflowPadding,
            ),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                item.label,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: selectionMenuLabelStyle(style, item.labelStyle),
              ),
            ),
          ),
        );
      },
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final scrolls =
            items.length * SelectionMenuMetrics.overflowRowHeight +
                _contentExtent >
            constraints.maxHeight;
        if (!scrolls) return list;
        final fade = math.min(
          SelectionMenuMetrics.edgeFade / math.max(constraints.maxHeight, 1),
          0.5,
        );
        return ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: const [
              Color(0x00000000),
              Color(0xFF000000),
              Color(0xFF000000),
              Color(0x00000000),
            ],
            stops: [0, fade, 1 - fade, 1],
          ).createShader(bounds),
          child: list,
        );
      },
    );
  }
}

// --- Back row ---

/// The More button, which is the back row once the page is open: the same
/// frame, the kebab giving way to the arrow, the label and the hairline
/// appearing with the progress.
class _BackRow extends StatelessWidget {
  const _BackRow({
    required this.progress,
    required this.open,
    required this.style,
    required this.tokens,
    required this.strings,
    required this.onPressed,
  });

  final double progress;
  final bool open;
  final TextStyle style;
  final SelectionMenuTokens tokens;
  final FormattingStrings strings;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final label = open ? strings.backAction : strings.moreAction;
    final hairline =
        SelectionMenuMetrics.dividerPhysicalPixels /
        MediaQuery.devicePixelRatioOf(context);
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: onPressed,
      child: Stack(
        children: [
          // The splash is the 40 dp circle around the icon while the page is
          // closed, in a 56 by 48 target; the whole row is the target once it
          // is open.
          PositionedDirectional(
            start: 0,
            top: 0,
            bottom: 0,
            width: open ? null : SelectionMenuMetrics.moreWidth,
            end: open ? 0 : null,
            child: InkResponse(
              key: const ValueKey<String>('selection_menu_back'),
              onTap: onPressed,
              containedInkWell: open,
              radius: SelectionMenuMetrics.splashRadius,
              customBorder: open ? null : const CircleBorder(),
              splashFactory: InkRipple.splashFactory,
              splashColor: tokens.pressHighlight,
              highlightColor: tokens.pressHighlight,
              hoverColor: tokens.pressHighlight,
              focusColor: tokens.pressHighlight,
              child: const SizedBox.expand(),
            ),
          ),
          PositionedDirectional(
            start: SelectionMenuMetrics.backIconInset,
            top:
                (SelectionMenuMetrics.moreHeight -
                    SelectionMenuMetrics.iconSize) /
                2,
            child: IgnorePointer(
              child: Stack(
                children: [
                  Opacity(
                    opacity: 1 - progress,
                    child: Icon(
                      Icons.more_vert,
                      size: SelectionMenuMetrics.iconSize,
                      color: tokens.text,
                    ),
                  ),
                  Opacity(
                    opacity: progress,
                    child: Icon(
                      Icons.arrow_back,
                      size: SelectionMenuMetrics.iconSize,
                      color: tokens.text,
                    ),
                  ),
                ],
              ),
            ),
          ),
          PositionedDirectional(
            start: SelectionMenuMetrics.backLabelInset,
            end: 0,
            top: 0,
            height: SelectionMenuMetrics.moreHeight,
            child: IgnorePointer(
              child: Opacity(
                opacity: progress,
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    strings.backAction,
                    maxLines: 1,
                    style: style.copyWith(
                      fontSize: SelectionMenuMetrics.backTextSize,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: hairline,
            child: Opacity(
              opacity: progress,
              child: ColoredBox(color: tokens.divider),
            ),
          ),
        ],
      ),
    );
  }
}
