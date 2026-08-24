import 'package:chat_chrome/src/theme/chat_chrome_colors.dart';
import 'package:emoji_data/emoji_data.dart';
import 'package:flutter/material.dart';

/// One category-strip tab (stable id + strip chrome).
@immutable
class EmojiCategoryStripTab {
  /// Creates a strip tab.
  const EmojiCategoryStripTab({required this.id, required this.icon});

  /// Stable section id (`recents`, `smileys`, …).
  final String id;

  /// Strip chrome from [EmojiCategorySpec.stripIcon] (or host recents icon).
  final EmojiStripIcon icon;
}

/// Category strip — 36dp strip with 30×30 cells and 24dp icons.
class EmojiCategoryStrip extends StatefulWidget {
  /// Creates the category strip.
  const EmojiCategoryStrip({
    required this.tabs,
    required this.selectedIndex,
    required this.onSelect,
    super.key,
  });

  /// Strip tabs in section order.
  final List<EmojiCategoryStripTab> tabs;

  /// Selected tab index.
  final int selectedIndex;

  /// Fired when the user taps a tab.
  final ValueChanged<int> onSelect;

  /// Strip height.
  static const double height = 36;

  /// Tab cell (`30×30`).
  static const double cell = 30;

  /// Drawn icon size.
  static const double iconSize = 24;

  /// Gap between cells.
  static const double gap = 3;

  /// Horizontal strip padding.
  static const double padH = 11;

  /// Ink ripple corner radius on the 30×30 cell.
  static const double inkRadius = 8;

  @override
  State<EmojiCategoryStrip> createState() => _EmojiCategoryStripState();
}

class _EmojiCategoryStripState extends State<EmojiCategoryStrip> {
  final ScrollController _scroll = ScrollController();

  @override
  void didUpdateWidget(EmojiCategoryStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex != widget.selectedIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _ensureSelectedVisible();
      });
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _ensureSelectedVisible() {
    if (!_scroll.hasClients) return;
    final i = widget.selectedIndex;
    if (i < 0 || i >= widget.tabs.length) return;
    final cellStart =
        EmojiCategoryStrip.padH +
        i * (EmojiCategoryStrip.cell + EmojiCategoryStrip.gap);
    final cellEnd = cellStart + EmojiCategoryStrip.cell;
    final viewStart = _scroll.offset;
    final viewEnd = viewStart + _scroll.position.viewportDimension;
    if (cellStart < viewStart) {
      _scroll.animateTo(
        cellStart - EmojiCategoryStrip.padH,
        duration: const Duration(milliseconds: 200),
        curve: Curves.decelerate,
      );
    } else if (cellEnd > viewEnd) {
      _scroll.animateTo(
        cellEnd - _scroll.position.viewportDimension + EmojiCategoryStrip.padH,
        duration: const Duration(milliseconds: 200),
        curve: Curves.decelerate,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = ChatChromeTheme.of(context);
    return SizedBox(
      height: EmojiCategoryStrip.height,
      child: ListView.separated(
        controller: _scroll,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: EmojiCategoryStrip.padH,
          vertical: 3,
        ),
        itemCount: widget.tabs.length,
        separatorBuilder: (_, _) =>
            const SizedBox(width: EmojiCategoryStrip.gap),
        itemBuilder: (context, index) {
          final selected = index == widget.selectedIndex;
          return _CategoryTab(
            icon: widget.tabs[index].icon,
            selected: selected,
            selectedColor: colors.panelIconSelected,
            idleColor: colors.panelIcon,
            onTap: () => widget.onSelect(index),
          );
        },
      ),
    );
  }
}

class _CategoryTab extends StatelessWidget {
  const _CategoryTab({
    required this.icon,
    required this.selected,
    required this.selectedColor,
    required this.idleColor,
    required this.onTap,
  });

  final EmojiStripIcon icon;
  final bool selected;
  final Color selectedColor;
  final Color idleColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(EmojiCategoryStrip.cell),
        onTap: onTap,
        child: SizedBox(
          width: EmojiCategoryStrip.cell,
          height: EmojiCategoryStrip.cell,
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: selected ? 1 : 0),
            duration: const Duration(milliseconds: 200),
            curve: Curves.decelerate,
            builder: (context, t, child) {
              final tint = Color.lerp(idleColor, selectedColor, t)!;
              return Stack(
                alignment: Alignment.center,
                children: <Widget>[
                  if (t > 0.01)
                    Opacity(
                      opacity: t,
                      child: Container(
                        width: EmojiCategoryStrip.cell,
                        height: EmojiCategoryStrip.cell,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: idleColor.withValues(alpha: 0.18),
                        ),
                      ),
                    ),
                  _StripIconVisual(icon: icon, tint: tint),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _StripIconVisual extends StatelessWidget {
  const _StripIconVisual({required this.icon, required this.tint});

  final EmojiStripIcon icon;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return switch (icon) {
      EmojiStripIconGlyph(:final glyph) => Text(
        glyph,
        style: TextStyle(
          fontSize: EmojiCategoryStrip.iconSize * 0.85,
          height: 1,
        ),
      ),
      EmojiStripIconAsset(:final assetPath, :final package) => Image.asset(
        assetPath,
        package: package,
        width: EmojiCategoryStrip.iconSize,
        height: EmojiCategoryStrip.iconSize,
        color: tint,
        colorBlendMode: BlendMode.srcIn,
        filterQuality: FilterQuality.medium,
      ),
      EmojiStripIconWidget(:final builder) => SizedBox(
        width: EmojiCategoryStrip.iconSize,
        height: EmojiCategoryStrip.iconSize,
        child: builder(context),
      ),
    };
  }
}

/// Category strip + gated shadow, slides up while the grid scrolls.
///
/// [shadowVisible] mirrors Telegram `checkEmojiShadow`: show when the strip
/// bottom sits over content (spacer scrolled under the strip line).
class EmojiCategoryStripOverlay extends StatelessWidget {
  /// Creates the overlay strip.
  const EmojiCategoryStripOverlay({
    required this.tabs,
    required this.selectedIndex,
    required this.onSelect,
    this.translationY = 0,
    this.shadowVisible = false,
    super.key,
  });

  /// Strip tabs.
  final List<EmojiCategoryStripTab> tabs;

  /// Active tab.
  final int selectedIndex;

  /// Tab tap.
  final ValueChanged<int> onSelect;

  /// Vertical slide 0…−[EmojiCategoryStrip.height].
  final double translationY;

  /// Whether the 1px shadow under the strip is shown.
  final bool shadowVisible;

  /// Glow / shadow probe below strip (`dp(38)` in Java).
  static const double shadowProbe = 38;

  @override
  Widget build(BuildContext context) {
    final colors = ChatChromeTheme.of(context);
    final y = translationY.clamp(-EmojiCategoryStrip.height, 0.0);
    return Transform.translate(
      offset: Offset(0, y),
      child: SizedBox(
        // Strip layout is 36 only — shadow paints below via Stack overflow
        // (Column + 1px made stripSize=37 and gapStripToSpacer≈−1).
        height: EmojiCategoryStrip.height,
        width: double.infinity,
        child: Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: EmojiCategoryStrip.height,
              child: ColoredBox(
                color: colors.panelBackground,
                child: EmojiCategoryStrip(
                  tabs: tabs,
                  selectedIndex: selectedIndex,
                  onSelect: onSelect,
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: EmojiCategoryStrip.height,
              child: _StripShadow(
                visible: shadowVisible,
                color: colors.panelShadowLine,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StripShadow extends StatefulWidget {
  const _StripShadow({required this.visible, required this.color});

  final bool visible;
  final Color color;

  @override
  State<_StripShadow> createState() => _StripShadowState();
}

class _StripShadowState extends State<_StripShadow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
      value: widget.visible ? 1 : 0,
    );
  }

  @override
  void didUpdateWidget(_StripShadow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visible == widget.visible) return;
    if (widget.visible) {
      _c.forward();
    } else {
      _c.reverse();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: CurvedAnimation(parent: _c, curve: Curves.easeOut),
      child: ColoredBox(color: widget.color, child: const SizedBox(height: 1)),
    );
  }
}
