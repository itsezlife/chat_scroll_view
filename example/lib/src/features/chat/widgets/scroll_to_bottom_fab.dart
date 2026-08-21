part of 'scroll_to_bottom_button.dart';

/// Test seam — present when chrome intends to be shown.
const Key chatScrollToBottomVisibleKey = ValueKey<String>(
  'scroll_to_bottom_visible',
);

/// Test seam — present when chrome intends to be hidden.
const Key chatScrollToBottomHiddenKey = ValueKey<String>(
  'scroll_to_bottom_hidden',
);

/// Round scroll-to-bottom control: frosted circle, optional unread badge,
/// show/hide (opacity + scale + slide), press scale with overshoot release.
class _ScrollToBottomFab extends StatefulWidget {
  const _ScrollToBottomFab({
    required this.count,
    required this.onTap,
    required this.visible,
    this.chromeVisible,
    this.animateVisibility = true,
  });

  final int count;
  final VoidCallback onTap;

  /// Drives opacity/scale/slide when [animateVisibility] is true.
  final bool visible;

  /// Show-intent for test keys when [animateVisibility] is false (embedded).
  final bool? chromeVisible;

  /// When false, paints at full opacity (parent stack owns hide animation).
  final bool animateVisibility;

  @override
  State<_ScrollToBottomFab> createState() => _ScrollToBottomFabState();
}

class _ScrollToBottomFabState extends State<_ScrollToBottomFab>
    with TickerProviderStateMixin {
  static const Duration _visibilityDuration = Duration(milliseconds: 280);
  static const Duration _pressInDuration = Duration(milliseconds: 80);
  static const Duration _pressOutDuration = Duration(milliseconds: 350);

  // Layout vs paint: the eye sees [_glassSize]; [_outerSize] is the touch box
  // (glass + hit padding). Badge sits in a band above the outer box.

  /// Painted frosted circle diameter.
  static const double _glassSize = 44;

  /// Transparent hit inset around the glass (each side).
  static const double _hitPadding = 6;

  /// Touch / layout box = glass + padding.
  static const double _outerSize = _glassSize + 2 * _hitPadding;

  /// Extra frame height above the outer box for the unread badge slot.
  static const double _counterBand = 8;

  static const double _frameHeight = _outerSize + _counterBand;

  /// Badge overlay strip at the top of the frame (overlaps the circle).
  static const double _counterSlotHeight = 28;

  /// Drawn chevron size (asset intrinsic logical size; not the hit box).
  static const double _iconIntrinsicWidth = 17;
  static const double _iconIntrinsicHeight = 10;

  /// Slight top pad so the chevron sits optically in the glass.
  static const double _iconPaddingTop = 2;

  static const double _hiddenScale = 0.7;
  static const double _slideAwayDp = 80;
  static const double _pressScaleDelta = 0.13;

  /// Scale pivot near the glass center (accounts for the badge band above).
  static const Alignment _scaleAlignment = Alignment(
    0,
    (_outerSize / 2 + _counterBand - _frameHeight / 2) / (_frameHeight / 2),
  );

  late final AnimationController _visibility;
  late final AnimationController _press;

  @override
  void initState() {
    super.initState();
    _visibility = AnimationController(
      vsync: this,
      duration: _visibilityDuration,
      value: (!widget.animateVisibility || widget.visible) ? 1.0 : 0.0,
    );
    _press = AnimationController(vsync: this, duration: _pressInDuration);
  }

  @override
  void didUpdateWidget(covariant _ScrollToBottomFab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.animateVisibility) {
      if (_visibility.value != 1.0) _visibility.value = 1.0;
      return;
    }
    if (oldWidget.visible != widget.visible) {
      _visibility.animateTo(
        widget.visible ? 1.0 : 0.0,
        duration: _visibilityDuration,
        curve: Curves.decelerate,
      );
    }
  }

  @override
  void dispose() {
    _visibility.dispose();
    _press.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails _) {
    _press
      ..duration = _pressInDuration
      ..animateTo(1, curve: Curves.linear);
  }

  void _onTapUp(TapUpDetails _) {
    _releasePress();
  }

  void _onTapCancel() {
    _releasePress();
  }

  void _releasePress() {
    _press
      ..duration = _pressOutDuration
      ..animateTo(0, curve: const OvershootCurve());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final chromeVisible = widget.chromeVisible ?? widget.visible;
    return KeyedSubtree(
      key: chromeVisible
          ? chatScrollToBottomVisibleKey
          : chatScrollToBottomHiddenKey,
      child: AnimatedBuilder(
        animation: Listenable.merge([_visibility, _press]),
        builder: (context, child) {
          final t = _visibility.value;
          final pressScale = 1.0 - _pressScaleDelta * _press.value;
          final visibilityScale = ui.lerpDouble(_hiddenScale, 1.0, t)!;
          return IgnorePointer(
            // Stay hittable until fully hidden.
            ignoring: t < 0.01,
            child: Opacity(
              opacity: t.clamp(0.0, 1.0),
              child: Transform.translate(
                offset: Offset(0, _slideAwayDp * (1 - t)),
                child: Transform.scale(
                  scale: visibilityScale * pressScale,
                  alignment: _scaleAlignment,
                  child: child,
                ),
              ),
            ),
          );
        },
        child: SizedBox(
          width: _outerSize,
          height: _frameHeight,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.bottomCenter,
            children: [
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: _outerSize,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onTap,
                  onTapDown: _onTapDown,
                  onTapUp: _onTapUp,
                  onTapCancel: _onTapCancel,
                  child: Center(
                    child: _GlassPageDownButton(
                      key: const ValueKey<String>('scroll_to_bottom'),
                      size: _glassSize,
                      iconColor: colorScheme.onSurfaceVariant,
                      glassColor: colorScheme.surfaceContainerHighest,
                    ),
                  ),
                ),
              ),
              // Full-width slot (like CounterView MATCH_PARENT): pill is painted
              // centered inside; widget width must not lerp or expand breaks.
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: _counterSlotHeight,
                child: Align(
                  alignment: Alignment.center,
                  child: ChatSideControlCounter(
                    count: widget.count,
                    seamKey: const ValueKey<String>('scroll_to_bottom_badge'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Frosted circular control with a downward chevron.
class _GlassPageDownButton extends StatelessWidget {
  const _GlassPageDownButton({
    required this.size,
    required this.iconColor,
    required this.glassColor,
    super.key,
  });

  final double size;
  final Color iconColor;
  final Color glassColor;

  @override
  Widget build(BuildContext context) => ClipOval(
    child: BackdropFilter(
      filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: glassColor.withValues(alpha: 0.72),
          border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        ),
        child: SizedBox(
          width: size,
          height: size,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.only(
                top: _ScrollToBottomFabState._iconPaddingTop,
              ),
              child: Image.asset(
                'assets/chat/pagedown.webp',
                width: _ScrollToBottomFabState._iconIntrinsicWidth,
                height: _ScrollToBottomFabState._iconIntrinsicHeight,
                color: iconColor,
                colorBlendMode: BlendMode.srcIn,
                filterQuality: FilterQuality.medium,
                errorBuilder: (context, error, stack) => Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: _ScrollToBottomFabState._iconIntrinsicWidth,
                  color: iconColor,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
