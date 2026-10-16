import 'dart:math' as math;

import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/foundation.dart' show clampDouble;
import 'package:flutter/widgets.dart';
import 'package:panel_shell/src/input/panel_intents.dart';
import 'package:panel_shell/src/page/panel_page.dart';

/// The pointer arrangement's page switcher: the reference desktop client's
/// tabs slider at the top of its emoji panel.
///
/// The column's width is shared equally by one section per page, each with
/// its name centred. The selected section is marked by a [barStroke] bar
/// across the whole section at its bottom, in the accent, which slides
/// linearly over [duration] to the next section; a label's colour goes from
/// the muted text colour to the accent as the bar comes over it. A press
/// grows a ripple from where it went down and the section is chosen when the
/// press is released over it (a press that leaves it chooses nothing). There
/// is no hover paint, the cursor is the click one, and a line runs under the
/// sections. Selecting goes through [PanelSelectPageIntent]; the tabs hold no
/// selection of their own.
///
/// The sizes are the reference client's slider as far as its source shows
/// them; its style values (the height, the bar, the font, the timings) are
/// not in the source available here and are taken from its defaults as
/// remembered.
class PanelSectionTabs extends StatefulWidget {
  /// Sections for [pages], [selectedPageId] marked.
  const PanelSectionTabs({
    required this.pages,
    required this.selectedPageId,
    super.key,
  });

  /// The pages, in order.
  final List<PanelPage> pages;

  /// The selected page.
  final String selectedPageId;

  /// Height of the tabs, the line under them included.
  static const double height = 53;

  /// Top of a label.
  static const double labelTop = 17;

  /// Top of the bar.
  static const double barTop = 50;

  /// Thickness of the bar.
  static const double barStroke = 3;

  /// Size of a label.
  static const double fontSize = 13;

  /// How long the bar takes to reach the next section.
  static const Duration duration = Duration(milliseconds: 150);

  /// How long a ripple takes to grow over its section.
  static const Duration rippleShow = Duration(milliseconds: 650);

  /// How long a released ripple takes to fade.
  static const Duration rippleHide = Duration(milliseconds: 200);

  /// Identifies the bar.
  @visibleForTesting
  static const Key barKey = ValueKey<String>('panel-section-tabs-bar');

  @override
  State<PanelSectionTabs> createState() => _PanelSectionTabsState();
}

class _PanelSectionTabsState extends State<PanelSectionTabs>
    with SingleTickerProviderStateMixin {
  late final AnimationController _slide = AnimationController(
    vsync: this,
    duration: PanelSectionTabs.duration,
    value: 1,
  );
  double _from = 0;
  double _to = 0;

  int get _selected =>
      widget.pages.indexWhere((page) => page.id == widget.selectedPageId);

  // Where the bar is, in sections.
  double get _position => _from + (_to - _from) * _slide.value;

  @override
  void initState() {
    super.initState();
    _from = _to = math.max(0, _selected).toDouble();
  }

  @override
  void didUpdateWidget(PanelSectionTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    final target = math.max(0, _selected).toDouble();
    if (target == _to) return;
    _from = _position;
    _to = target;
    final duration = ChromeMotionScope.of(
      context,
    ).speed.scale(PanelSectionTabs.duration);
    if (MediaQuery.disableAnimationsOf(context) || duration == Duration.zero) {
      _from = _to;
      _slide.value = 1;
    } else {
      _slide
        ..duration = duration
        ..forward(from: 0);
    }
  }

  @override
  void dispose() {
    _slide.dispose();
    super.dispose();
  }

  void _select(PanelPage page) => Actions.maybeInvoke<PanelSelectPageIntent>(
    context,
    PanelSelectPageIntent(page.id),
  );

  @override
  Widget build(BuildContext context) {
    final palette = ChromeThemeScope.paletteOf(context);
    final panel = ChromeThemeScope.panelOf(context);
    final strings = ChromeStringsScope.panelOf(context);
    return SizedBox(
      height: PanelSectionTabs.height,
      child: LayoutBuilder(
        builder: (context, box) {
          final count = widget.pages.length;
          final section = box.maxWidth / count;
          // Sections read in the text direction: the first page at the start.
          final rtl = Directionality.of(context) == TextDirection.rtl;
          double leftOf(double index) =>
              (rtl ? count - 1 - index : index) * section;
          return AnimatedBuilder(
            animation: _slide,
            builder: (context, _) {
              final position = _position;
              return Stack(
                children: [
                  for (var i = 0; i < count; i++)
                    Positioned(
                      left: leftOf(i.toDouble()),
                      top: 0,
                      width: section,
                      height: PanelSectionTabs.height,
                      child: _Section(
                        label: strings.tabLabel(widget.pages[i].tab.labelKey),
                        selected: i == _selected,
                        active: 1 - clampDouble((position - i).abs(), 0, 1),
                        muted: palette.onSurfaceMuted,
                        accent: palette.accent,
                        ripple: palette.onSurface.withAlpha(0x12),
                        onSelect: () => _select(widget.pages[i]),
                      ),
                    ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: 1,
                    child: IgnorePointer(
                      child: ColoredBox(color: panel.hairline),
                    ),
                  ),
                  Positioned(
                    key: PanelSectionTabs.barKey,
                    left: leftOf(position),
                    top: PanelSectionTabs.barTop,
                    width: section,
                    height: PanelSectionTabs.barStroke,
                    child: IgnorePointer(
                      child: ColoredBox(color: palette.accent),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _Section extends StatefulWidget {
  const _Section({
    required this.label,
    required this.selected,
    required this.active,
    required this.muted,
    required this.accent,
    required this.ripple,
    required this.onSelect,
  });

  final String label;
  final bool selected;
  final double active;
  final Color muted;
  final Color accent;
  final Color ripple;
  final VoidCallback onSelect;

  @override
  State<_Section> createState() => _SectionState();
}

class _SectionState extends State<_Section> with TickerProviderStateMixin {
  late final AnimationController _grow = AnimationController(
    vsync: this,
    duration: PanelSectionTabs.rippleShow,
  );
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: PanelSectionTabs.rippleHide,
    value: 1,
  );
  Offset? _origin;
  var _focused = false;

  @override
  void dispose() {
    _grow.dispose();
    _fade.dispose();
    super.dispose();
  }

  void _down(TapDownDetails details) {
    setState(() => _origin = details.localPosition);
    _fade.value = 0;
    _grow.forward(from: 0);
  }

  void _release() => _fade.forward(from: 0);

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: widget.selected,
    label: widget.label,
    onTap: widget.onSelect,
    excludeSemantics: true,
    // Reached by the keyboard like any control, Enter or Space choosing it.
    child: FocusableActionDetector(
      mouseCursor: SystemMouseCursors.click,
      onShowFocusHighlight: (show) => setState(() => _focused = show),
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onSelect();
            return null;
          },
        ),
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: _down,
        onTapUp: (_) {
          _release();
          widget.onSelect();
        },
        onTapCancel: _release,
        child: ClipRect(
          child: CustomPaint(
            foregroundPainter: _focused
                ? _FocusRingPainter(widget.accent)
                : null,
            painter: _RipplePainter(
              origin: _origin,
              grow: _grow,
              fade: _fade,
              color: widget.ripple,
            ),
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  top: PanelSectionTabs.labelTop,
                  child: Text(
                    widget.label,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: PanelSectionTabs.fontSize,
                      fontWeight: FontWeight.w600,
                      color: Color.lerp(
                        widget.muted,
                        widget.accent,
                        widget.active,
                      ),
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

// A circle from where the press went down, growing to cover the section and
// fading once the press is over.
class _RipplePainter extends CustomPainter {
  _RipplePainter({
    required this.origin,
    required this.grow,
    required this.fade,
    required this.color,
  }) : super(repaint: Listenable.merge([grow, fade]));

  final Offset? origin;
  final Animation<double> grow;
  final Animation<double> fade;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = origin;
    if (center == null || fade.value >= 1) return;
    final reach = [
      Offset.zero,
      Offset(size.width, 0),
      Offset(0, size.height),
      Offset(size.width, size.height),
    ].map((corner) => (corner - center).distance).reduce(math.max);
    canvas.drawCircle(
      center,
      reach * Curves.easeOut.transform(grow.value),
      Paint()..color = color.withValues(alpha: color.a * (1 - fade.value)),
    );
  }

  @override
  bool shouldRepaint(_RipplePainter old) =>
      old.origin != origin || old.color != color;
}

// The keyboard focus of a section: a ring inside its edges.
class _FocusRingPainter extends CustomPainter {
  const _FocusRingPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) => canvas.drawRect(
    (Offset.zero & size).deflate(1),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = color,
  );

  @override
  bool shouldRepaint(_FocusRingPainter old) => old.color != color;
}
