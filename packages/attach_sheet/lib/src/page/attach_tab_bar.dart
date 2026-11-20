import 'dart:async';
import 'dart:math' as math;

import 'package:attach_sheet/src/page/attach_page.dart';
import 'package:attach_sheet/src/page/attach_pages_sheet.dart';
import 'package:attach_sheet/src/policy/attach_tab_bar_style.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

/// The text size of a tab's label.
const double _labelSize = 12;

/// The sheet's tab bar: one tab per page, by the policy's style. A single
/// page collapses it; a host page's main button replaces it; it leaves
/// while the attach selection is not empty.
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
  final ScrollController _$strip = ScrollController();
  Curve _hideCurve = Curves.linear;

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
  }

  @override
  void dispose() {
    _model.selection.changes.removeListener(_selectionChanged);
    _model.active.removeListener(_activeChanged);
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
    final hide = _model.selection.isNotEmpty;
    final spec = (hide ? _style.hideMotion : _style.showMotion).withSpeed(
      _speed,
    );
    _hideCurve = spec.curve;
    unawaited(_$hidden.animateTo(hide ? 1 : 0, duration: spec.duration));
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
    final labels = [
      for (final page in _model.pages.pages)
        (TextPainter(
          text: TextSpan(
            text: page.label,
            style: ChromeTypography.of(context).copyWith(fontSize: _labelSize),
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
        return Padding(
          padding: EdgeInsets.fromLTRB(
            _style.sidePadding,
            8,
            _style.sidePadding,
            8 + padding.bottom,
          ),
          child: _MainButton(button: button, style: _style),
        );
      }
      if (pages.length < 2) return const SizedBox.shrink();
      return AnimatedBuilder(
        animation: _$hidden,
        builder: (context, bar) {
          final h = _hideCurve.transform(_$hidden.value);
          return IgnorePointer(
            ignoring: _$hidden.value > 0,
            child: Opacity(
              opacity: 1 - h,
              child: Transform.translate(
                offset: Offset(0, _style.hideDrop * h),
                child: Transform.scale(
                  scale: 1 - (1 - _style.hideScale) * h,
                  child: bar,
                ),
              ),
            ),
          );
        },
        child: Padding(
          padding: EdgeInsets.only(bottom: padding.bottom + 8),
          child: _bar(context),
        ),
      );
    },
  );

  Widget _bar(BuildContext context) {
    final palette = ChromeThemeScope.paletteOf(context);
    final width = MediaQuery.sizeOf(context).width;
    final widths = _widths(width);
    final pages = _model.pages.pages;
    final tabsWidth = widths.fold<double>(0, (a, b) => a + b);
    final barWidth = math.min(
      tabsWidth + 2 * _style.innerPadding,
      width - 2 * _style.sidePadding,
    );
    final lens = _style.lens;
    if (lens != null && !_lensPlaced) {
      _lensPlaced = true;
      _$lens.value = _lensX(widths, _activeIndex);
    }
    Widget row = Row(
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
              selected: pages[i].id == _model.active.value,
              fillsSelected: lens == null,
              badges: _style.permissionBadges,
              onTap: () => _model.select(pages[i].id),
              palette: palette,
            ),
          ),
      ],
    );
    if (lens != null) {
      // The lens sits under the tabs and follows a drag across them; the
      // tab under the finger when it lifts is selected.
      final lensHeight =
          _style.height - 2 * _style.innerPadding - 2 * lens.inset;
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
                      material: GlassMaterial.panelButton,
                      cornerRadius: lens.radius,
                      child: const SizedBox.expand(),
                    ),
                  );
                },
              ),
              row,
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
    return Center(
      child: GlassSurface(
        material: GlassMaterial.composerIsland,
        cornerRadius: _style.radius,
        child: Container(
          key: const ValueKey('attach-tab-bar'),
          width: barWidth,
          height: _style.height,
          padding: EdgeInsets.all(_style.innerPadding),
          child: fade > 0 && clipped
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
              : strip,
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.page,
    required this.width,
    required this.selected,
    required this.fillsSelected,
    required this.badges,
    required this.onTap,
    required this.palette,
  });

  final AttachPage page;
  final double width;
  final bool selected;
  final bool fillsSelected;
  final bool badges;
  final VoidCallback onTap;
  final ChromePalette palette;

  @override
  Widget build(BuildContext context) {
    final color = selected ? palette.accent : palette.onSurfaceMuted;
    final permission = page.permission;
    var icon = IconTheme.merge(
      data: IconThemeData(color: color, size: 24),
      child: page.icon,
    );
    if (badges && permission != null) {
      icon = ValueListenableBuilder<bool>(
        valueListenable: permission.granted,
        child: icon,
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
                      label: ChromeStringsScope.attachOf(
                        context,
                      ).permissionNeeded,
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
    return Semantics(
      button: true,
      selected: selected,
      label: page.label,
      child: GestureDetector(
        key: ValueKey('attach-tab-${page.id}'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: width,
          decoration: BoxDecoration(
            color: selected && fillsSelected ? palette.surfaceSelected : null,
            borderRadius: BorderRadius.circular(28),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              icon,
              const SizedBox(height: 2),
              Text(
                page.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ChromeTypography.of(
                  context,
                ).copyWith(color: color, fontSize: _labelSize),
              ),
            ],
          ),
        ),
      ),
    );
  }
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
