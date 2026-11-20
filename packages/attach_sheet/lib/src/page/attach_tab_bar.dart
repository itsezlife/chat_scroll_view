import 'dart:async';
import 'dart:math' as math;

import 'package:attach_sheet/src/page/attach_page.dart';
import 'package:attach_sheet/src/page/attach_pages_sheet.dart';
import 'package:attach_sheet/src/policy/attach_tab_bar_style.dart';
import 'package:attach_sheet/src/sheet/attach_sheet.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

/// The sheet's tab bar: one tab per page, by the policy's style. A single
/// page collapses it; a host page's main button replaces it; it leaves
/// while the attach selection is not empty.
///
/// It leaves and comes back on one factor: its glass's own opacity (never
/// an opacity layer over the glass, which would hide the scene from it),
/// its tabs' opacity, its drop and its scale.
@internal
class AttachTabBar extends StatefulWidget {
  /// The tab bar of [model].
  const AttachTabBar({required this.model, super.key});

  /// The pages' state.
  final AttachPagesModel model;

  @override
  State<AttachTabBar> createState() => _AttachTabBarState();
}

class _AttachTabBarState extends State<AttachTabBar>
    with TickerProviderStateMixin {
  late final AnimationController _$hidden = AnimationController(vsync: this);
  late final AnimationController _$popIn = AnimationController(vsync: this);
  late final AnimationController _$lens = AnimationController.unbounded(
    vsync: this,
  );
  bool _lensPlaced = false;
  int? _dragIndex;

  /// How far the bar drops at the hidden end: the selection's drop, or the
  /// sheet's top's while that hides it.
  late double _drop = _style.hideDrop;
  final ScrollController _$strip = ScrollController();

  AttachPagesModel get _model => widget.model;
  AttachTabBarStyle get _style => _model.policy.tabBar;

  @override
  void initState() {
    super.initState();
    _model.selection.changes.addListener(_selectionChanged);
    _model.active.addListener(_activeChanged);
    if (_model.selection.isNotEmpty) _$hidden.value = 1;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_$popIn.value == 0 && !_$popIn.isAnimating) _startPopIn();
    final sheet = AttachSheetController.maybeOf(context);
    if (!identical(sheet, _sheet)) {
      _sheet?.top.removeListener(_topChanged);
      _sheet = sheet;
      sheet?.top.addListener(_topChanged);
    }
  }

  AttachSheetController? _sheet;
  // The sheet opens from below: not at its top until it has risen there.
  bool _pinned = false;

  // While the sheet is at its top the bar leaves (on a policy that hides
  // it there) and comes back as the sheet leaves the top.
  void _topChanged() {
    final pinned = _sheet?.isExpanded ?? false;
    if (pinned == _pinned) return;
    _pinned = pinned;
    final motion = _style.pinnedHide;
    if (motion == null || _model.selection.isNotEmpty) return;
    _drop = _style.pinnedDrop ?? _style.hideDrop;
    final spec = motion.withSpeed(_speed);
    // Eased on time either way, from wherever the bar is.
    unawaited(
      _$hidden.animateTo(
        pinned ? 1 : 0,
        duration: spec.duration,
        curve: spec.curve,
      ),
    );
  }

  bool get _hiddenByPin => _pinned && _style.pinnedHide != null;

  @override
  void dispose() {
    _model.selection.changes.removeListener(_selectionChanged);
    _model.active.removeListener(_activeChanged);
    _sheet?.top.removeListener(_topChanged);
    _$hidden.dispose();
    _$popIn.dispose();
    _$lens.dispose();
    _$strip.dispose();
    super.dispose();
  }

  ChromeMotionSpeed get _speed => ChromeMotionScope.of(context).speed;

  void _startPopIn() {
    final popIn = _style.popIn;
    if (popIn == null || _speed.isInstant) {
      _$popIn.value = 1;
      return;
    }
    // The controller runs over the whole pop-in, its delay included;
    // [AttachTabPopIn.at] reads each tab from the elapsed time.
    final total = popIn.delay + popIn.total;
    _$popIn.duration = total;
    unawaited(_$popIn.forward());
  }

  void _selectionChanged() {
    final hide = _model.selection.isNotEmpty || _hiddenByPin;
    _drop = _model.selection.isEmpty && _hiddenByPin
        ? _style.pinnedDrop ?? _style.hideDrop
        : _style.hideDrop;
    final spec = (hide ? _style.hideMotion : _style.showMotion).withSpeed(
      _speed,
    );
    unawaited(
      _$hidden.animateTo(
        hide ? 1 : 0,
        duration: spec.duration,
        curve: spec.curve,
      ),
    );
  }

  void _activeChanged() {
    setState(() {});
    _slideLens();
    final clearance = _style.scrollClearance;
    if (clearance <= 0 || !_$strip.hasClients) return;
    final index = _model.pages.pages.indexWhere(
      (p) => p.id == _model.active.value,
    );
    final widths = _widths(MediaQuery.sizeOf(context).width);
    final start = widths.take(index).fold<double>(0, (a, b) => a + b);
    final end = start + widths[index];
    final position = _$strip.position;
    final viewport = position.viewportDimension;
    var target = position.pixels;
    if (start - clearance < target) target = start - clearance;
    if (end + clearance > target + viewport)
      target = end + clearance - viewport;
    target = target.clamp(0, position.maxScrollExtent);
    if (target == position.pixels) return;
    unawaited(
      _$strip.animateTo(
        target,
        duration: _speed.scale(const Duration(milliseconds: 250)),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  int get _activeIndex =>
      _model.pages.pages.indexWhere((p) => p.id == _model.active.value);

  /// The lens's left edge over tab [index] of [widths].
  double _lensX(List<double> widths, int index) =>
      widths.take(index).fold<double>(0, (a, b) => a + b) +
      (_style.lens?.inset ?? 0);

  /// Slides the lens to the shown tab on the lens's spring.
  void _slideLens() {
    final lens = _style.lens;
    if (lens == null || !mounted) return;
    final widths = _widths(MediaQuery.sizeOf(context).width);
    final target = _lensX(widths, _activeIndex);
    if (_speed.isInstant) {
      _$lens.value = target;
      return;
    }
    unawaited(
      _$lens
          .animateWith(
            SpringSimulation(
              lens.spring,
              _$lens.value,
              target,
              _$lens.velocity,
            ),
          )
          .orCancel
          .then((_) => _$lens.value = target, onError: (Object _) {}),
    );
  }

  /// The tab under [dx] in the strip.
  int _indexAt(List<double> widths, double dx) {
    var start = 0.0;
    for (var i = 0; i < widths.length; i++) {
      start += widths[i];
      if (dx < start) return i;
    }
    return widths.length - 1;
  }

  void _dragLens(List<double> widths, double dx) {
    final lens = _style.lens!;
    final index = _indexAt(widths, dx);
    _dragIndex = index;
    final half = (widths[index] - 2 * lens.inset) / 2;
    final total = widths.fold<double>(0, (a, b) => a + b);
    _$lens.value = (dx - half).clamp(
      lens.inset,
      total - widths.last + lens.inset,
    );
  }

  void _dropLens() {
    final index = _dragIndex;
    _dragIndex = null;
    if (index == null) return;
    final id = _model.pages.pages[index].id;
    if (id == _model.active.value) {
      _slideLens();
    } else {
      _model.select(id);
      // A tab the model would not switch to (a permission to ask for, a
      // switch running) leaves the lens where the shown tab is.
      if (_model.active.value != id) _slideLens();
    }
  }

  List<double> _widths(double screenWidth) {
    final tab = _style.tab;
    final labels = [
      for (final page in _model.pages.pages)
        (TextPainter(
          text: TextSpan(
            text: page.label,
            style: ChromeTypography.of(context).copyWith(
              fontSize: tab.measuredLabelSize,
              fontWeight: tab.labelWeight,
            ),
          ),
          textDirection: TextDirection.ltr,
          maxLines: 1,
        )..layout()).width,
    ];
    final available =
        screenWidth - 2 * _style.sidePadding - 2 * _style.innerPadding;
    return _model.policy.tabWidths(labels, available);
  }

  @override
  Widget build(BuildContext context) {
    final pages = _model.pages.pages;
    final padding = MediaQuery.paddingOf(context);
    return ValueListenableBuilder<bool>(
      valueListenable: _model.panelHidden,
      builder: (context, hidden, _) => hidden
          ? const SizedBox.shrink()
          : _barOrButton(context, pages, padding),
    );
  }

  Widget _barOrButton(
    BuildContext context,
    List<AttachPage> pages,
    EdgeInsets padding,
  ) => ValueListenableBuilder<AttachMainButton?>(
    valueListenable: _model.mainButton,
    builder: (context, button, _) {
      if (button != null) {
        // Its sides line up with the tabs'.
        final side = _style.sidePadding + _style.innerPadding;
        return Padding(
          padding: EdgeInsets.fromLTRB(side, 8, side, 8 + padding.bottom),
          child: _MainButton(button: button, style: _style),
        );
      }
      if (pages.length < 2) return const SizedBox.shrink();
      return AnimatedBuilder(
        animation: _$hidden,
        builder: (context, _) {
          final h = _$hidden.value;
          return IgnorePointer(
            ignoring: h > 0,
            child: Transform.translate(
              offset: Offset(0, _drop * h),
              child: Transform.scale(
                scale: 1 - (1 - _style.hideScale) * h,
                child: Padding(
                  padding: EdgeInsets.only(
                    bottom: padding.bottom + _style.bottomPadding,
                  ),
                  child: _bar(context, 1 - h),
                ),
              ),
            ),
          );
        },
      );
    },
  );

  /// The bar, its glass and its tabs at [shown] opacity.
  Widget _bar(BuildContext context, double shown) {
    final colors = _style.colors(
      ChromeThemeScope.paletteOf(context),
      ChromeThemeScope.attachOf(context),
    );
    final width = MediaQuery.sizeOf(context).width;
    final widths = _widths(width);
    final pages = _model.pages.pages;
    final tabsWidth = widths.fold<double>(0, (a, b) => a + b);
    final barWidth = math.min(
      tabsWidth + 2 * _style.innerPadding,
      width - 2 * _style.sidePadding,
    );
    final tabHeight = _style.height - 2 * _style.innerPadding;
    final lens = _style.lens;
    if (lens != null && !_lensPlaced) {
      _lensPlaced = true;
      _$lens.value = _lensX(widths, _activeIndex);
    }
    Widget row = Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < pages.length; i++)
          AnimatedBuilder(
            animation: _$popIn,
            builder: (context, tab) {
              final popIn = _style.popIn;
              if (popIn == null) return tab!;
              final elapsed = (popIn.delay + popIn.total) * _$popIn.value;
              final at = popIn.at(i, elapsed - popIn.delay);
              return Opacity(
                opacity: at.opacity.clamp(0.0, 1.0),
                child: Transform.scale(
                  key: ValueKey('attach-tab-pop-${pages[i].id}'),
                  scale: at.scale,
                  child: tab,
                ),
              );
            },
            child: _Tab(
              page: pages[i],
              width: widths[i],
              height: tabHeight,
              selected: pages[i].id == _model.active.value,
              badges: _style.permissionBadges,
              onTap: () => _model.select(pages[i].id),
              colors: colors,
              style: _style.tab,
            ),
          ),
      ],
    );
    // The tabs fade with the glass; a glass among them (the lens) fades by
    // its own opacity, outside their fade.
    row = Opacity(opacity: shown, child: row);
    if (lens != null) {
      // The lens sits under the tabs and follows a drag across them; the
      // tab under the finger when it lifts is selected.
      final lensHeight = tabHeight - 2 * lens.inset;
      row = GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: (d) => _dragLens(widths, d.localPosition.dx),
        onHorizontalDragUpdate: (d) => _dragLens(widths, d.localPosition.dx),
        onHorizontalDragEnd: (_) => _dropLens(),
        onHorizontalDragCancel: _dropLens,
        child: SizedBox(
          width: tabsWidth,
          child: Stack(
            children: [
              AnimatedBuilder(
                animation: _$lens,
                builder: (context, _) {
                  final index = _dragIndex ?? _activeIndex;
                  return Positioned(
                    left: _$lens.value,
                    top: lens.inset,
                    width: widths[index] - 2 * lens.inset,
                    height: lensHeight,
                    child: GlassSurface(
                      key: const ValueKey('attach-tab-lens'),
                      material: GlassMaterial.button,
                      cornerRadius: lens.radius,
                      opacity: shown,
                      child: const SizedBox.expand(),
                    ),
                  );
                },
              ),
              Positioned.fill(child: row),
            ],
          ),
        ),
      );
    }
    final strip = SingleChildScrollView(
      controller: _$strip,
      scrollDirection: Axis.horizontal,
      physics: lens == null ? null : const NeverScrollableScrollPhysics(),
      child: row,
    );
    final fade = _style.edgeFade;
    final clipped = tabsWidth > barWidth - 2 * _style.innerPadding;
    final faded = fade > 0 && clipped
        ? ShaderMask(
            shaderCallback: (rect) => LinearGradient(
              colors: const [
                Color(0x00000000),
                Color(0xFF000000),
                Color(0xFF000000),
                Color(0x00000000),
              ],
              stops: [0, fade / rect.width, 1 - fade / rect.width, 1],
            ).createShader(rect),
            blendMode: BlendMode.dstIn,
            child: strip,
          )
        : strip;
    // The tabs clip to the bar's stadium, inset by the inner padding.
    final tabs = lens == null
        ? ClipRRect(
            borderRadius: BorderRadius.circular(_style.radius),
            child: faded,
          )
        : faded;
    return Center(
      child: SizedBox(
        key: const ValueKey('attach-tab-bar'),
        width: barWidth,
        height: _style.height,
        child: Stack(
          children: [
            Positioned.fill(
              child: GlassSurface(
                key: const ValueKey('attach-tab-bar-glass'),
                material: _style.glass,
                colors: _style.glassColors,
                cornerRadius: _style.radius,
                opacity: shown,
                child: const SizedBox.expand(),
              ),
            ),
            Positioned.fill(
              child: Padding(
                padding: EdgeInsets.all(_style.innerPadding),
                child: tabs,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One tab: its mark, its press wash, its icon and its label, coloured by
/// one select factor that eases between shown and not.
class _Tab extends StatefulWidget {
  const _Tab({
    required this.page,
    required this.width,
    required this.height,
    required this.selected,
    required this.badges,
    required this.onTap,
    required this.colors,
    required this.style,
  });

  final AttachPage page;
  final double width;
  final double height;
  final bool selected;
  final bool badges;
  final VoidCallback onTap;
  final AttachTabColors colors;
  final AttachTabStyle style;

  @override
  State<_Tab> createState() => _TabState();
}

class _TabState extends State<_Tab> with TickerProviderStateMixin {
  // Time through the current select move; the factor eases from [_from] to
  // [_to] along it, so a move turned back starts where the last one was.
  late final AnimationController _$select = AnimationController(
    vsync: this,
    value: 1,
  );
  late final AnimationController _$press = AnimationController(vsync: this);
  late double _from = widget.selected ? 1 : 0;
  late double _to = _from;

  double get _factor =>
      _from +
      (_to - _from) * widget.style.selectMotion.curve.transform(_$select.value);

  @override
  void didUpdateWidget(_Tab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selected == oldWidget.selected) return;
    _from = _factor;
    _to = widget.selected ? 1 : 0;
    final spec = widget.style.selectMotion.withSpeed(
      ChromeMotionScope.of(context).speed,
    );
    if (spec.duration == Duration.zero) {
      _$select.value = 1;
      return;
    }
    _$select
      ..duration = spec.duration
      ..forward(from: 0).ignore();
  }

  @override
  void dispose() {
    _$select.dispose();
    _$press.dispose();
    super.dispose();
  }

  void _pressDown() {
    if (widget.style.pressFade == null) return;
    _$press.value = 1;
  }

  void _pressUp() {
    final fade = widget.style.pressFade;
    if (fade == null || _$press.value == 0) return;
    _$press
        .animateTo(0, duration: ChromeMotionScope.of(context).speed.scale(fade))
        .ignore();
  }

  @override
  Widget build(BuildContext context) {
    final page = widget.page;
    final style = widget.style;
    final colors = widget.colors;
    final permission = page.permission;
    final palette = ChromeThemeScope.paletteOf(context);
    return Semantics(
      button: true,
      selected: widget.selected,
      label: page.label,
      child: GestureDetector(
        key: ValueKey('attach-tab-${page.id}'),
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _pressDown(),
        onTapUp: (_) => _pressUp(),
        onTapCancel: _pressUp,
        onTap: widget.onTap,
        child: SizedBox(
          width: widget.width,
          child: AnimatedBuilder(
            animation: _$select,
            builder: (context, _) {
              final f = _factor;
              final iconColor = Color.lerp(
                colors.unselected,
                colors.selected,
                f,
              )!;
              final tinted = IconTheme.merge(
                data: IconThemeData(color: iconColor, size: style.iconSize),
                child: widget.selected
                    ? page.selectedIcon ?? page.icon
                    : page.icon,
              );
              final icon = widget.badges && permission != null
                  ? _Badged(
                      granted: permission.granted,
                      palette: palette,
                      child: tinted,
                    )
                  : tinted;
              final indicator = style.indicator;
              return Stack(
                children: [
                  if (indicator != null)
                    Positioned.fill(
                      child: Transform.scale(
                        key: ValueKey('attach-tab-indicator-${page.id}'),
                        scale:
                            indicator.fromScale + (1 - indicator.fromScale) * f,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: colors.indicator.withValues(
                              alpha:
                                  colors.indicator.a *
                                  Curves.decelerate.transform(f),
                            ),
                            borderRadius: BorderRadius.circular(
                              math.min(widget.width, widget.height) / 2,
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (style.pressFade != null)
                    Positioned.fill(
                      child: AnimatedBuilder(
                        animation: _$press,
                        builder: (context, wash) => Opacity(
                          key: ValueKey('attach-tab-press-${page.id}'),
                          opacity: _$press.value,
                          child: wash,
                        ),
                        child: ColoredBox(color: colors.pressed),
                      ),
                    ),
                  Positioned(
                    top: style.iconTop,
                    left: 0,
                    right: 0,
                    height: style.iconSize,
                    child: Center(
                      child: SizedBox(
                        key: ValueKey('attach-tab-icon-${page.id}'),
                        width: style.iconSize,
                        height: style.iconSize,
                        child: icon,
                      ),
                    ),
                  ),
                  Positioned(
                    top: style.labelTop,
                    left: style.labelPadding,
                    right: style.labelPadding,
                    child: Text(
                      page.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: ChromeTypography.of(context).copyWith(
                        color: Color.lerp(
                          colors.unselected,
                          colors.selectedLabel,
                          f,
                        ),
                        fontSize: style.labelSize,
                        fontWeight: widget.selected
                            ? style.selectedLabelWeight
                            : style.labelWeight,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// [child] with a badge while [granted] is false.
class _Badged extends StatelessWidget {
  const _Badged({
    required this.granted,
    required this.palette,
    required this.child,
  });

  final ValueListenable<bool> granted;
  final ChromePalette palette;
  final Widget child;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: granted,
    child: child,
    builder: (context, granted, icon) => granted
        ? icon!
        : Stack(
            clipBehavior: Clip.none,
            children: [
              icon!,
              PositionedDirectional(
                top: -4,
                end: -8,
                child: Semantics(
                  label: ChromeStringsScope.attachOf(context).permissionNeeded,
                  child: Container(
                    key: const ValueKey('attach-tab-badge'),
                    width: 16,
                    height: 16,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: palette.destructive,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '!',
                      style: ChromeTypography.of(context).copyWith(
                        color: palette.onAccent,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
  );
}

class _MainButton extends StatelessWidget {
  const _MainButton({required this.button, required this.style});

  final AttachMainButton button;
  final AttachTabBarStyle style;

  @override
  Widget build(BuildContext context) {
    final palette = ChromeThemeScope.paletteOf(context);
    return Semantics(
      button: true,
      child: GestureDetector(
        key: const ValueKey('attach-main-button'),
        behavior: HitTestBehavior.opaque,
        onTap: button.onPressed,
        child: Container(
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: palette.accent,
            borderRadius: BorderRadius.circular(style.radius),
          ),
          child: Text(
            button.label,
            style: ChromeTypography.of(context).copyWith(
              color: palette.onAccent,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
