import 'dart:ui' as ui;

import 'package:chat_chrome/src/glass/liquid_glass_shader.dart';
import 'package:chat_chrome/src/glass/telegram_glass_style.dart';
import 'package:flutter/material.dart';

/// Floating chrome shell with Telegram-style liquid glass.
///
/// Uses scene [BackdropFilter] (frost → blur → liquid). Hosts must keep
/// [ChatContentBottomFade] **under** this island with an island-shaped
/// cutout so the wash is not sampled into the glass.
class TelegramGlass extends StatefulWidget {
  /// Creates a glass surface around [child].
  const TelegramGlass({required this.style, required this.child, super.key});

  /// Material tokens (radius, tint, strokes, liquid params).
  final TelegramGlassStyle style;

  /// Content drawn above the glass. Sizes the surface.
  final Widget child;

  @override
  State<TelegramGlass> createState() => _TelegramGlassState();
}

class _TelegramGlassState extends State<TelegramGlass> {
  GlassShaderPrograms? _programs;
  Object? _loadError;

  @override
  void initState() {
    super.initState();
    _loadShader();
  }

  @override
  void didUpdateWidget(covariant TelegramGlass oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.style.enableLiquid != widget.style.enableLiquid) {
      _loadShader();
    }
  }

  Future<void> _loadShader() async {
    if (!widget.style.enableLiquid) return;
    try {
      final programs = await LiquidGlassShader.load();
      if (!mounted) return;
      setState(() {
        _programs = programs;
        _loadError = null;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _loadError = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style;
    final radius = BorderRadius.circular(style.cornerRadius);
    final shadow = style.shadowColor.a > 0
        ? <BoxShadow>[
            BoxShadow(
              color: style.shadowColor,
              blurRadius: style.shadowBlur,
              offset: style.shadowOffset,
            ),
          ]
        : const <BoxShadow>[];

    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: radius, boxShadow: shadow),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return _SceneGlassBackdrop(
                    style: style,
                    size: constraints.biggest,
                    programs: _programs,
                    loadError: _loadError,
                  );
                },
              ),
            ),
            Positioned.fill(
              child: CustomPaint(painter: _GlassStrokePainter(style: style)),
            ),
            widget.child,
          ],
        ),
      ),
    );
  }
}

class _SceneGlassBackdrop extends StatelessWidget {
  const _SceneGlassBackdrop({
    required this.style,
    required this.size,
    required this.programs,
    required this.loadError,
  });

  final TelegramGlassStyle style;
  final Size size;
  final GlassShaderPrograms? programs;
  final Object? loadError;

  @override
  Widget build(BuildContext context) {
    final useLiquid =
        style.enableLiquid &&
        programs != null &&
        loadError == null &&
        LiquidGlassShader.isSupported;
    final filter = useLiquid
        ? LiquidGlassShader.createFilter(
            programs: programs!,
            size: size,
            style: style,
          )
        : null;

    if (filter != null) {
      return BackdropFilter(
        filter: filter,
        child: const ColoredBox(color: Color(0x00000000)),
      );
    }

    return BackdropFilter(
      filter: ui.ImageFilter.blur(
        sigmaX: style.effectiveBlurSigma,
        sigmaY: style.effectiveBlurSigma,
        tileMode: TileMode.clamp,
      ),
      child: ColoredBox(color: style.fill),
    );
  }
}

/// Dual top/bottom stroke matching Android glass edge chrome.
class _GlassStrokePainter extends CustomPainter {
  _GlassStrokePainter({required this.style});

  final TelegramGlassStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final radius = style.cornerRadius;
    final rect = Offset.zero & size;

    _paintStroke(
      canvas: canvas,
      rect: rect,
      radius: radius,
      strokeWidth: style.strokeWidthTop,
      color: style.strokeTop,
      isTop: true,
    );
    _paintStroke(
      canvas: canvas,
      rect: rect,
      radius: radius,
      strokeWidth: style.strokeWidthBottom,
      color: style.strokeBottom,
      isTop: false,
    );
  }

  void _paintStroke({
    required Canvas canvas,
    required Rect rect,
    required double radius,
    required double strokeWidth,
    required Color color,
    required bool isTop,
  }) {
    if (strokeWidth <= 0 || color.a == 0) return;
    final half = strokeWidth / 2;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..isAntiAlias = true;

    canvas.save();
    if (isTop) {
      canvas.clipRect(
        Rect.fromLTRB(
          rect.left,
          rect.top,
          rect.right,
          (rect.top + radius * 2).clamp(rect.top, rect.bottom),
        ),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(
            rect.left - half,
            rect.top + half,
            rect.right + half,
            rect.bottom + half,
          ),
          Radius.circular(radius),
        ),
        paint,
      );
    } else {
      canvas.clipRect(
        Rect.fromLTRB(
          rect.left,
          (rect.bottom - radius * 2).clamp(rect.top, rect.bottom),
          rect.right,
          rect.bottom,
        ),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(
            rect.left - half,
            rect.top - half,
            rect.right + half,
            rect.bottom - half,
          ),
          Radius.circular(radius),
        ),
        paint,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _GlassStrokePainter oldDelegate) =>
      oldDelegate.style != style;
}
