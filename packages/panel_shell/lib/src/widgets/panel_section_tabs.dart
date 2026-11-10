import 'dart:math' as math;

import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/foundation.dart' show clampDouble;
import 'package:flutter/gestures.dart' show PointerDeviceKind, kPrimaryButton;
import 'package:flutter/widgets.dart';
import 'package:panel_shell/src/input/panel_intents.dart';
import 'package:panel_shell/src/page/panel_page.dart';

/// The pointer arrangement's page switcher: a tabs slider at the top of the
/// panel.
///
/// The column's width is shared equally by one section per page, each with
/// its name centred. The selected section is marked by a [barStroke] bar in
/// the accent near its bottom, as wide as its label with rounded top corners
/// ([PanelSectionTabsBar.label]) or across the whole
/// section ([PanelSectionTabsBar.section]); it slides linearly over
/// [duration] to the next one, taking its width. A label's colour goes from
/// the muted text colour to the accent as the bar comes over it. A press
/// grows a ripple from where it went down and the section is chosen when the
/// press is released over it (a press that leaves it chooses nothing). There
/// is no hover paint, the cursor is the click one, and a line runs under the
/// sections. Selecting goes through [PanelSelectPageIntent]; the tabs hold no
/// selection of their own.
///
/// The style values (the height, the bar, the font, the timings) are the
/// slider's defaults.
class PanelSectionTabs extends StatefulWidget {
  /// Sections for [pages], [selectedPageId] marked.
  const PanelSectionTabs({
    required this.pages,
    required this.selectedPageId,
    this.bar = PanelSectionTabsBar.label,
    super.key,
  });

  /// How wide the bar is.
  final PanelSectionTabsBar bar;

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

  /// Radius of a label-wide bar's top corners.
  static const double barRadius = 2;

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

  static TextStyle get _labelStyle => const TextStyle(
    fontSize: PanelSectionTabs.fontSize,
    fontWeight: FontWeight.w600,
  );

  static double _labelWidth(String label, TextScaler scaler) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: _labelStyle),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  // The bar at [position] (in sections): across the section, or as wide as
  // the labels it is between, centred under them.
  Widget _bar({
    required double position,
    required double section,
    required double Function(double index) leftOf,
    required List<double> widths,
    required Color color,
  }) {
    final (left, width, radius) = switch (widget.bar) {
      PanelSectionTabsBar.section => (leftOf(position), section, 0.0),
      PanelSectionTabsBar.label => () {
        final from = position.floor().clamp(0, widths.length - 1);
        final to = position.ceil().clamp(0, widths.length - 1);
        final t = position - from;
        final width = widths[from] + (widths[to] - widths[from]) * t;
        return (
          leftOf(position) + (section - width) / 2,
          width,
          PanelSectionTabs.barRadius,
        );
      }(),
    };
    return Positioned(
      key: PanelSectionTabs.barKey,
      left: left,
      top: PanelSectionTabs.barTop,
      width: width,
      height: PanelSectionTabs.barStroke,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.vertical(top: Radius.circular(radius)),
          ),
        ),
      ),
    );
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
          // Each section's label width, measured as it is drawn.
          final labels = [
            for (final page in widget.pages)
              strings.tabLabel(page.tab.labelKey),
          ];
          final scaler = MediaQuery.textScalerOf(context);
          final widths = [
            for (final label in labels)
              math.min(section, _labelWidth(label, scaler)),
          ];
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
                        label: labels[i],
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
                  _bar(
                    position: position,
                    section: section,
                    leftOf: leftOf,
                    widths: widths,
                    color: palette.accent,
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

class _SectionState extends State<_Section> {
  var _focused = false;
  var _primary = true;

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
      // The desktop ink: a ripple from the press over 650 ms, fading over
      // 200 ms; no hover fill.
      // Only the primary button chooses: the ink takes every button.
      child: Listener(
        onPointerDown: (event) => _primary =
            event.buttons & kPrimaryButton != 0 ||
            event.kind != PointerDeviceKind.mouse,
        child: ChromeInk(
          kind: ChromeInkKind.pointer,
          color: widget.ripple,
          onTap: () {
            if (_primary) widget.onSelect();
          },
          child: ClipRect(
            child: CustomPaint(
              foregroundPainter: _focused
                  ? _FocusRingPainter(widget.accent)
                  : null,
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
                      style: _PanelSectionTabsState._labelStyle.copyWith(
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
    ),
  );
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

/// How wide the bar under the selected section tab is.
enum PanelSectionTabsBar {
  /// As wide as the label, with rounded top corners.
  label,

  /// Across the whole section.
  section,
}
