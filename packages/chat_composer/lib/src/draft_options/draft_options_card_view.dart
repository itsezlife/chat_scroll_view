import 'dart:async';

import 'package:chat_composer/src/draft_options/draft_link_part.dart';
import 'package:chat_composer/src/draft_options/draft_options_card.dart';
import 'package:chat_composer/src/draft_options/draft_options_session.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// The Android presentation of the draft options overlay: a card over the
/// whole window holding a header and the live [preview] in its list, with
/// the [menu] in a glass under it, placed by [layout] and moved by
/// [motion].
///
/// The overlay opens by fading in and scaling up about its centre (not from
/// the strip) and closes the reverse way when the [scrim] starts to close;
/// the scrim's fade bounds how long the overlay stays. The card clips from
/// its visible top, and a press on the band above it lands on the scrim, so
/// it closes the overlay like any press outside. A changed preview moves
/// the card's visible top and centring after [DraftOptionsCardMotion]'s
/// delay, and a change of position or size then scrolls the list to the
/// card's end (top when the card is above the text).
///
/// The menu's glass samples the scrim's glass source with the scrim menu
/// colours. Every motion reports through [session] (`motion`) and follows
/// the chrome motion speed: under an instant speed each lands on its end.
class DraftOptionsCardView extends StatefulWidget {
  /// The card of [session] over [scrim].
  const DraftOptionsCardView({
    required this.session,
    required this.scrim,
    required this.layout,
    required this.motion,
    required this.preview,
    this.title,
    this.subtitle,
    this.menu,
    super.key,
  });

  /// The key of the card's surface.
  static const Key cardKey = ValueKey('draftOptionsCard');

  /// The key of the menu's glass.
  static const Key menuKey = ValueKey('draftOptionsCardMenu');

  /// The key of the card's header bar.
  static const Key headerKey = ValueKey('draftOptionsCardHeader');

  /// The open's value and its events.
  final DraftOptionsSession session;

  /// The scrim under the card; its close starts the card's.
  final ChromeScrimController scrim;

  /// Where the card and the menu stand.
  final DraftOptionsCardLayout layout;

  /// How the card moves.
  final DraftOptionsCardMotion motion;

  /// The live preview, at the bottom of the card's list.
  final Widget preview;

  /// The header's title; with no title there is no header bar.
  final String? title;

  /// The header's subtitle under the title.
  final String? subtitle;

  /// The menu's content (the page's rows); null shows no menu.
  final Widget? menu;

  @override
  State<DraftOptionsCardView> createState() => _DraftOptionsCardViewState();
}

class _DraftOptionsCardViewState extends State<DraftOptionsCardView>
    with TickerProviderStateMixin {
  late final AnimationController _appear = AnimationController(vsync: this);
  late final CurvedAnimation _appearEased = CurvedAnimation(
    parent: _appear,
    curve: widget.motion.open.curve,
    reverseCurve: widget.motion.close.curve.flipped,
  );
  late final AnimationController _offsets = AnimationController(vsync: this);
  late final CurvedAnimation _offsetsEased = CurvedAnimation(
    parent: _offsets,
    curve: widget.motion.offsets.curve,
  );
  final ScrollController _scroll = ScrollController();
  Timer? _offsetsDelay;
  var _closing = false;
  var _started = false;

  // What the layout reads: the area, the display, the measured menu glass
  // and preview. The preview and menu report their sizes after a layout, so
  // the placement follows one frame later; a change waits for the offsets'
  // delay anyway, and the open starts transparent.
  Size? _area;
  double _display = 0;
  Size _menuSize = Size.zero;
  double _content = 0;
  var _measured = false;
  var _measureScheduled = false;

  // The placement moves from [_from] to [_to] on [_offsets].
  DraftOptionsCardGeometry? _from;
  DraftOptionsCardGeometry? _to;
  DraftLinkPart? _shownValue;

  DraftOptionsSession get _session => widget.session;
  DraftOptionsCardLayout get _layout => widget.layout;
  DraftOptionsCardMotion get _motion => widget.motion;

  @override
  void initState() {
    super.initState();
    _offsets.value = 1;
    widget.scrim.addListener(_onScrim);
    _shownValue = _session.value.value;
    _session.value.addListener(_onValue);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final speed = ChromeMotionScope.of(context).speed;
    final duration = speed.scale(_motion.open.duration);
    _appear
      ..duration = duration
      ..reverseDuration = speed.scale(_motion.close.duration);
    _session.reportMotion(
      DraftOptionsMotionPhase.open,
      duration,
      reduceMotion: speed.isInstant,
    );
    unawaited(_appear.forward());
    _onScrim();
  }

  @override
  void dispose() {
    widget.scrim.removeListener(_onScrim);
    _session.value.removeListener(_onValue);
    _offsetsDelay?.cancel();
    _appearEased.dispose();
    _offsetsEased.dispose();
    _appear.dispose();
    _offsets.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // --- Open and close ---

  void _onScrim() {
    if (_closing || !widget.scrim.isClosing || !mounted) return;
    _closing = true;
    final speed = ChromeMotionScope.of(context).speed;
    _session.reportMotion(
      DraftOptionsMotionPhase.close,
      speed.scale(_motion.close.duration),
      reduceMotion: speed.isInstant,
    );
    unawaited(_appear.reverse());
  }

  // --- Following a change ---

  void _onValue() {
    final next = _session.value.value;
    final previous = _shownValue;
    _shownValue = next;
    if (previous == null) return;
    final moved =
        previous.invertMedia != next.invertMedia ||
        previous.options.media != next.options.media;
    if (!moved) return;
    // After the layout of the changed preview, as the list scrolls once it
    // has laid the change out.
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToEnd(next));
  }

  void _scrollToEnd(DraftLinkPart part) {
    if (!mounted || !_scroll.hasClients) return;
    final position = _scroll.position;
    if (position.maxScrollExtent <= 0) return;
    // The list is reversed: 0 is its bottom.
    final target = part.invertMedia ? position.maxScrollExtent : 0.0;
    final speed = ChromeMotionScope.of(context).speed;
    final duration = speed.scale(_motion.scroll.duration);
    if (duration == Duration.zero) {
      _scroll.jumpTo(target);
      return;
    }
    unawaited(
      _scroll.animateTo(
        target,
        duration: duration,
        curve: _motion.scroll.curve,
      ),
    );
  }

  void _onMenuSize(Size size) {
    if (size == _menuSize) return;
    _menuSize = size;
    _scheduleMeasure();
  }

  void _onContentSize(Size size) {
    if (size.height == _content) return;
    _content = size.height;
    _scheduleMeasure();
  }

  void _scheduleMeasure() {
    if (_measureScheduled) return;
    _measureScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureScheduled = false;
      if (mounted) _retarget();
    });
  }

  DraftOptionsCardGeometry? _resolve() => switch (_area) {
    final area? => _layout.resolve(
      area: area,
      display: _display,
      menu: _menuSize,
      content: _content,
    ),
    null => null,
  };

  DraftOptionsCardGeometry? get _current => switch ((_from, _to)) {
    (final from?, final to?) => DraftOptionsCardGeometry.lerp(
      from,
      to,
      _offsetsEased.value,
    ),
    _ => _to,
  };

  // The measured sizes changed: the first measure places the card at once,
  // a later one moves it after the delay.
  void _retarget() {
    final target = _resolve();
    if (target == null || target == _to) return;
    if (!_measured) {
      _measured = true;
      setState(() => _from = _to = target);
      return;
    }
    final speed = ChromeMotionScope.of(context).speed;
    final duration = speed.scale(_motion.offsets.duration);
    _offsetsDelay?.cancel();
    if (speed.isInstant) {
      _session.reportMotion(
        DraftOptionsMotionPhase.change,
        duration,
        reduceMotion: true,
      );
      setState(() => _from = _to = target);
      return;
    }
    final now = _current;
    _offsets.value = 0;
    setState(() {
      _from = now;
      _to = target;
    });
    _offsetsDelay = Timer(speed.scale(_motion.offsetsDelay), () {
      if (!mounted) return;
      _session.reportMotion(
        DraftOptionsMotionPhase.change,
        duration,
        reduceMotion: false,
      );
      _offsets.duration = duration;
      unawaited(_offsets.forward(from: 0));
    });
  }

  // --- Build ---

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    _display = MediaQuery.sizeOf(context).height;
    return Padding(
      padding: EdgeInsets.only(top: padding.top, bottom: padding.bottom),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final area = constraints.biggest;
          if (area != _area) {
            // A new area (a rotation, a resize) places the card at once.
            _area = area;
            _from = _to = _resolve();
          }
          return AnimatedBuilder(
            animation: Listenable.merge([_appearEased, _offsetsEased]),
            builder: (context, _) => _frame(context, _current!),
          );
        },
      ),
    );
  }

  Widget _frame(BuildContext context, DraftOptionsCardGeometry geometry) {
    final appear = _appearEased.value;
    final scale = _motion.openScale + (1 - _motion.openScale) * appear;
    return Transform.scale(
      scale: scale,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fromRect(
            rect: geometry.card,
            child: Opacity(opacity: appear, child: _card(context, geometry)),
          ),
          if (widget.menu case final menu?)
            Positioned(
              left: geometry.menu.left,
              top: geometry.menu.top,
              child: Padding(
                padding: EdgeInsets.all(_layout.menuPadding),
                child: _menu(context, menu, appear),
              ),
            ),
        ],
      ),
    );
  }

  Widget _card(BuildContext context, DraftOptionsCardGeometry geometry) {
    final palette = ChromeThemeScope.paletteOf(context);
    final clipper = _VisibleCardClipper(
      top: geometry.topOffset,
      radius: _layout.cornerRadius,
    );
    final list = Positioned(
      left: 0,
      right: 0,
      top: _layout.headerHeight,
      bottom: 0,
      child: SingleChildScrollView(
        controller: _scroll,
        reverse: true,
        padding: EdgeInsets.symmetric(vertical: _layout.listPadding),
        child: _SizeReport(onSize: _onContentSize, child: widget.preview),
      ),
    );
    return PhysicalShape(
      key: DraftOptionsCardView.cardKey,
      clipper: clipper,
      clipBehavior: Clip.antiAlias,
      elevation: _layout.elevation,
      color: palette.surface,
      shadowColor: const Color(0xFF000000),
      child: ColoredBox(
        color: palette.surface,
        child: Stack(
          children: [
            list,
            if (widget.title case final title?)
              Positioned(
                left: 0,
                right: 0,
                top: geometry.topOffset,
                height: _layout.headerHeight,
                child: _header(context, title),
              ),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context, String title) {
    final palette = ChromeThemeScope.paletteOf(context);
    final style = ChromeTypography.of(context);
    return ColoredBox(
      key: DraftOptionsCardView.headerKey,
      color: palette.surfaceRaised,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: _layout.headerPadding),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style.copyWith(
                fontSize: _layout.titleSize,
                fontWeight: FontWeight.bold,
                color: palette.onSurface,
              ),
            ),
            ?switch (widget.subtitle) {
              final subtitle? => Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style.copyWith(
                  fontSize: _layout.subtitleSize,
                  color: palette.onSurfaceMuted,
                ),
              ),
              null => null,
            },
          ],
        ),
      ),
    );
  }

  Widget _menu(BuildContext context, Widget menu, double appear) {
    final palette = ChromeThemeScope.paletteOf(context);
    // The glass fades by its own opacity: an opacity layer over it would
    // hide what it samples until the fade ends.
    return GlassSurface(
      key: DraftOptionsCardView.menuKey,
      material: GlassMaterial.scrimMenu,
      colors: GlassMaterialColors.scrimMenu(palette),
      cornerRadius: _layout.menuRadius,
      opacity: appear,
      child: _SizeReport(onSize: _onMenuSize, child: menu),
    );
  }
}

/// The card's outline from its visible top down: the band above is cut
/// away, so it neither paints nor takes a press (which then reaches the
/// scrim and closes the overlay).
final class _VisibleCardClipper extends CustomClipper<Path> {
  const _VisibleCardClipper({required this.top, required this.radius});

  final double top;
  final double radius;

  @override
  Path getClip(Size size) => Path()
    ..addRRect(
      RRect.fromLTRBR(
        0,
        top.clamp(0, size.height),
        size.width,
        size.height,
        Radius.circular(radius),
      ),
    );

  @override
  bool shouldReclip(_VisibleCardClipper oldClipper) =>
      oldClipper.top != top || oldClipper.radius != radius;
}

/// Tells [onSize] its child's size after each layout that changed it.
class _SizeReport extends SingleChildRenderObjectWidget {
  const _SizeReport({required this.onSize, super.child});

  final ValueChanged<Size> onSize;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderSizeReport(onSize);

  @override
  void updateRenderObject(BuildContext context, _RenderSizeReport render) =>
      render.onSize = onSize;
}

class _RenderSizeReport extends RenderProxyBox {
  _RenderSizeReport(this.onSize);

  ValueChanged<Size> onSize;
  Size? _reported;

  @override
  void performLayout() {
    super.performLayout();
    if (size == _reported) return;
    _reported = size;
    // The owner only stores it and schedules its own rebuild after the
    // frame: nothing is rebuilt during this layout.
    onSize(size);
  }
}
