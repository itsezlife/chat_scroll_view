import 'dart:math' as math;

import 'package:chrome_foundation/src/menu/pointer_menu_entry.dart';
import 'package:chrome_foundation/src/menu/pointer_menu_metrics.dart';
import 'package:chrome_foundation/src/motion/pointer_menu_motion.dart';
import 'package:chrome_foundation/src/tokens/pointer_menu_tokens.dart';
import 'package:flutter/widgets.dart';

/// The key of the row showing the item [id], in any pointer menu.
final class PointerMenuRowKey extends ValueKey<Object> {
  /// The key of the row of [id].
  const PointerMenuRowKey(super.value);
}

/// The key of the panel of the menu or submenu at [level] (0 is the root).
final class PointerMenuPanelKey extends ValueKey<int> {
  /// The key of the panel at [level].
  const PointerMenuPanelKey(super.value);
}

/// The width a row asks of its panel: label, then the hint or the arrow, with
/// the padding between, before the panel's clamp.
double pointerMenuRowWidth({
  required PointerMenuItem item,
  required TextStyle style,
  required TextDirection textDirection,
  required TextScaler textScaler,
}) {
  double measure(String text) => (TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: textDirection,
    textScaler: textScaler,
    maxLines: 1,
  )..layout()).width;
  final label = measure(PointerMenuLabel.parse(item.label).text);
  const start = PointerMenuMetrics.labelStart;
  const end = PointerMenuMetrics.labelEnd;
  const gap = PointerMenuMetrics.hintGap;
  if (item.submenu != null) {
    return start + label + gap + PointerMenuMetrics.arrowBox + end;
  }
  final hint = item.hint;
  if (hint != null) return start + label + gap + measure(hint) + end;
  return start + label + end;
}

/// One chooseable row of a pointer menu: the label with its mnemonic
/// underlined, a hint or an arrow at the trailing edge, the hover fill and the
/// press ripple.
///
/// The row reports; the menu decides. A row that cannot be chosen takes no
/// hover and no ripple and draws in the disabled colour.
class PointerMenuRow extends StatefulWidget {
  /// A row for [item].
  const PointerMenuRow({
    required this.item,
    required this.tokens,
    required this.style,
    required this.highlighted,
    required this.rippleEnabled,
    required this.onHover,
    required this.onExit,
    required this.onPress,
    required this.onRelease,
    super.key,
  });

  /// What the row shows.
  final PointerMenuItem item;

  /// Colours.
  final PointerMenuTokens tokens;

  /// The label style: size, family; the colour is the tokens'.
  final TextStyle style;

  /// Whether the row is the menu's selected one.
  final bool highlighted;

  /// Whether a press draws a ripple (off under reduce-motion).
  final bool rippleEnabled;

  /// The pointer moved over the row, at the global position.
  final ValueChanged<Offset> onHover;

  /// The pointer left the row.
  final VoidCallback onExit;

  /// A button went down on the row; true when the menu takes the press (the
  /// ripple starts only then).
  final bool Function() onPress;

  /// A button came up on the row.
  final VoidCallback onRelease;

  @override
  State<PointerMenuRow> createState() => _PointerMenuRowState();
}

class _PointerMenuRowState extends State<PointerMenuRow>
    with TickerProviderStateMixin {
  late final AnimationController _grow = AnimationController(
    vsync: this,
    duration: PointerMenuTiming.rippleGrow,
  );
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: PointerMenuTiming.rippleFade,
  );
  Offset _rippleOrigin = Offset.zero;
  var _pressed = false;

  @override
  void dispose() {
    _grow.dispose();
    _fade.dispose();
    super.dispose();
  }

  void _down(PointerDownEvent event) {
    if (!widget.item.isEnabled) return;
    final taken = widget.onPress();
    if (!taken || !widget.rippleEnabled) return;
    _pressed = true;
    _rippleOrigin = event.localPosition;
    _fade.reset();
    _grow.forward(from: 0);
  }

  void _up(PointerEvent event) {
    if (_pressed) {
      _pressed = false;
      _fade.forward(from: 0);
    }
    if (event is PointerUpEvent) widget.onRelease();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final tokens = widget.tokens;
    final enabled = item.isEnabled;
    final over = enabled && widget.highlighted;
    final label = PointerMenuLabel.parse(item.label);
    final textColor = !enabled
        ? tokens.textDisabled
        : over
        ? tokens.textOver
        : tokens.text;
    final hintColor = !enabled
        ? tokens.textDisabled
        : over
        ? tokens.hintOver
        : tokens.hint;
    // The decoration's colour and style are set outright: an outer text style
    // without a Material ancestor draws a yellow double underline, which a
    // span that only sets `decoration` would inherit.
    final style = widget.style.copyWith(
      color: textColor,
      decorationColor: textColor,
      decorationStyle: TextDecorationStyle.solid,
    );
    final mnemonic = label.mnemonic;
    final text = mnemonic == null
        ? TextSpan(text: label.text, style: style)
        : TextSpan(
            style: style,
            children: [
              TextSpan(text: label.text.substring(0, mnemonic)),
              TextSpan(
                text: label.text.substring(mnemonic, mnemonic + 1),
                style: const TextStyle(decoration: TextDecoration.underline),
              ),
              TextSpan(text: label.text.substring(mnemonic + 1)),
            ],
          );
    final hint = item.hint;
    final hasArrow = item.submenu != null;
    return Semantics(
      container: true,
      button: true,
      enabled: enabled,
      selected: over,
      label: label.text,
      hint: hint,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        onHover: (event) => widget.onHover(event.position),
        onExit: (_) => widget.onExit(),
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _down,
          onPointerUp: _up,
          onPointerCancel: _up,
          child: SizedBox(
            height: PointerMenuMetrics.rowHeight,
            child: CustomPaint(
              painter: _RowPainter(
                fill: over ? tokens.backgroundOver : tokens.background,
                ripple: tokens.ripple,
                origin: _rippleOrigin,
                grow: _grow,
                fade: _fade,
                active: enabled,
              ),
              child: Padding(
                padding: const EdgeInsetsDirectional.only(
                  start: PointerMenuMetrics.labelStart,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: EdgeInsetsDirectional.only(
                          end: hasArrow
                              ? PointerMenuMetrics.hintGap * 2 +
                                    PointerMenuMetrics.arrowBox
                              : hint != null
                              ? PointerMenuMetrics.hintGap
                              : PointerMenuMetrics.labelEnd,
                        ),
                        child: Text.rich(
                          text,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    if (hint != null)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(
                          end: PointerMenuMetrics.labelEnd,
                        ),
                        child: Text(
                          hint,
                          maxLines: 1,
                          softWrap: false,
                          style: widget.style.copyWith(color: hintColor),
                        ),
                      ),
                    if (hasArrow)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(
                          end: PointerMenuMetrics.hintGap,
                        ),
                        child: CustomPaint(
                          size: const Size.square(PointerMenuMetrics.arrowBox),
                          painter: _ArrowPainter(
                            color: enabled ? tokens.arrow : tokens.textDisabled,
                            mirrored:
                                Directionality.of(context) == TextDirection.rtl,
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
}

// The row's background and its ripple, repainted by the two controllers.
class _RowPainter extends CustomPainter {
  _RowPainter({
    required this.fill,
    required this.ripple,
    required this.origin,
    required this.grow,
    required this.fade,
    required this.active,
  }) : super(repaint: Listenable.merge([grow, fade]));

  final Color fill;
  final Color ripple;
  final Offset origin;
  final Animation<double> grow;
  final Animation<double> fade;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = fill);
    if (!active || grow.value == 0 || fade.value == 1) return;
    final farthest = [
      origin,
      Offset(size.width, 0) - origin,
      Offset(0, size.height) - origin,
      size.bottomRight(Offset.zero) - origin,
    ].map((corner) => corner.distance).reduce(math.max);
    final radius = farthest * Curves.easeOutQuint.transform(grow.value);
    canvas
      ..save()
      ..clipRect(Offset.zero & size)
      ..drawCircle(
        origin,
        radius,
        Paint()..color = ripple.withValues(alpha: ripple.a * (1 - fade.value)),
      )
      ..restore();
  }

  @override
  bool shouldRepaint(_RowPainter old) =>
      old.fill != fill ||
      old.ripple != ripple ||
      old.origin != origin ||
      old.active != active;
}

// The submenu chevron: a 5 x 10 stroke at x 9..14, y 7..16 of the 24 px box
// (the reference's `menu/submenu_arrow` mask measured). The stroke width is
// UNVERIFIED (a mask has no stroke): 1.5.
class _ArrowPainter extends CustomPainter {
  const _ArrowPainter({required this.color, required this.mirrored});

  final Color color;
  final bool mirrored;

  @override
  void paint(Canvas canvas, Size size) {
    double x(double v) => mirrored ? size.width - v : v;
    final path = Path()
      ..moveTo(x(9), 7)
      ..lineTo(x(14), 11.5)
      ..lineTo(x(9), 16);
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_ArrowPainter old) =>
      old.color != color || old.mirrored != mirrored;
}
