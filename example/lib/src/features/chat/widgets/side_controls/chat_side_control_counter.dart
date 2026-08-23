import 'dart:math' as math;

import 'package:chat_scroll_view_example/src/features/chat/widgets/side_controls/overshoot_curve.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';

/// Count pill for side-control FABs (page-down unread, search hits, …).
///
/// Drawn with a single [TextPainter] (measure + paint). Count changes animate:
/// appear (scale + overshoot), dismiss (scale down), replace (width lerp,
/// vertical digit slide, stable digits stay put, light pop on increase).
/// Jumps larger than 99 snap without animation.
class ChatSideControlCounter extends StatefulWidget {
  /// Creates an animated count pill (`0` collapses).
  const ChatSideControlCounter({required this.count, this.seamKey, super.key});

  /// Displayed count; `≤ 0` hides the pill.
  final int count;

  /// Optional semantics / test seam for the invisible layout text.
  final Key? seamKey;

  /// Painted pill height (logical px).
  static const double height = 23;

  @override
  State<ChatSideControlCounter> createState() => _ChatSideControlCounterState();
}

enum _CounterAnim { none, fadeIn, fadeOut, replace }

class _ChatSideControlCounterState extends State<ChatSideControlCounter>
    with SingleTickerProviderStateMixin {
  static const Color _background = Color(0xFF229AF0);
  static const Color _foreground = Color(0xFFFFFFFF);
  static const double _radius = 11.5;
  static const double _height = ChatSideControlCounter.height;
  static const double _extraWidth = _radius - 0.5; // 11
  static const double _minTextSlot = 12;
  static const int _skipAnimDelta = 99;

  /// Ease-out cubic used for replace / dismiss.
  static const Curve _defaultCurve = Cubic(0.25, 0.1, 0.25, 1);

  late final AnimationController _controller;

  int _currentCount = 0;
  String _currentText = '';
  double _countWidth = 0;
  double _countWidthOld = 0;
  _CounterAnim _anim = _CounterAnim.none;
  bool _increment = false;

  TextPainter? _layout;
  TextPainter? _oldLayout;
  TextPainter? _inLayout;
  TextPainter? _stableLayout;

  static TextStyle get _textStyle {
    const base = TextStyle(
      color: _foreground,
      fontSize: 13,
      fontWeight: FontWeight.w500,
    );
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => base.copyWith(fontFamily: 'sans-serif-medium'),
      _ => base.copyWith(
        fontFamily: 'Roboto',
        fontFamilyFallback: const ['SF Pro Text', 'Helvetica Neue', 'Arial'],
      ),
    };
  }

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this)
      ..addStatusListener(_onStatus);
    // First mount with unread: play appear animation from an empty badge.
    _applyCount(widget.count, animated: widget.count > 0);
  }

  @override
  void didUpdateWidget(covariant ChatSideControlCounter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.count != widget.count) {
      _applyCount(widget.count, animated: true);
    }
  }

  @override
  void dispose() {
    _controller
      ..removeStatusListener(_onStatus)
      ..dispose();
    _disposePainters();
    super.dispose();
  }

  void _onStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    _oldLayout?.dispose();
    _inLayout?.dispose();
    _stableLayout?.dispose();
    _oldLayout = null;
    _inLayout = null;
    _stableLayout = null;
    _anim = _CounterAnim.none;
    if (_currentCount <= 0) {
      _layout?.dispose();
      _layout = null;
      _countWidth = 0;
      _currentText = '';
    }
    if (mounted) setState(() {});
  }

  void _disposePainters() {
    _layout?.dispose();
    _oldLayout?.dispose();
    _inLayout?.dispose();
    _stableLayout?.dispose();
  }

  double _measureSlot(String text) {
    final painter = _painter(TextSpan(text: text, style: _textStyle))..layout();
    final slot = math.max(_minTextSlot, painter.width.ceilToDouble());
    painter.dispose();
    return slot;
  }

  TextPainter _painter(InlineSpan span) => TextPainter(
    text: span,
    textDirection: TextDirection.ltr,
    textAlign: TextAlign.center,
    maxLines: 1,
  );

  /// Keep glyph advance; hide ink (unchanged digits during replace).
  InlineSpan _stubbed(String text, bool Function(int i) hide) {
    final style = _textStyle;
    final clear = style.copyWith(color: const Color(0x00000000));
    return TextSpan(
      children: [
        for (var i = 0; i < text.length; i++)
          TextSpan(text: text[i], style: hide(i) ? clear : style),
      ],
    );
  }

  void _applyCount(int count, {required bool animated}) {
    final text = count > 0 ? '$count' : '';
    if (text == _currentText && count == _currentCount) return;

    _controller.stop();

    var runAnim = animated;
    if ((count - _currentCount).abs() > _skipAnimDelta) {
      runAnim = false;
    }

    if (!runAnim) {
      _anim = _CounterAnim.none;
      _controller.value = 1;
      _oldLayout?.dispose();
      _inLayout?.dispose();
      _stableLayout?.dispose();
      _oldLayout = null;
      _inLayout = null;
      _stableLayout = null;
      _currentCount = count;
      _currentText = text;
      if (count <= 0) {
        _layout?.dispose();
        _layout = null;
        _countWidth = 0;
      } else {
        _countWidth = _measureSlot(text);
        _layout?.dispose();
        _layout = _painter(TextSpan(text: text, style: _textStyle))
          ..layout(minWidth: _countWidth, maxWidth: _countWidth);
      }
      if (mounted) setState(() {});
      return;
    }

    final oldText = _currentText;
    final hadLayout = _layout != null;

    if (_currentCount <= 0) {
      _anim = _CounterAnim.fadeIn;
      _controller
        ..duration = const Duration(milliseconds: 220)
        ..value = 0;
    } else if (count <= 0) {
      _anim = _CounterAnim.fadeOut;
      _controller
        ..duration = const Duration(milliseconds: 150)
        ..value = 0;
    } else {
      _anim = _CounterAnim.replace;
      _controller
        ..duration = const Duration(milliseconds: 430)
        ..value = 0;
    }

    _oldLayout?.dispose();
    _inLayout?.dispose();
    _stableLayout?.dispose();
    _oldLayout = null;
    _inLayout = null;
    _stableLayout = null;

    if (hadLayout && _anim == _CounterAnim.replace) {
      if (oldText.length == text.length) {
        final oldWidth = math.max(_minTextSlot, _countWidth);
        _oldLayout = _painter(_stubbed(oldText, (i) => oldText[i] == text[i]))
          ..layout(minWidth: oldWidth, maxWidth: oldWidth);
        _inLayout = _painter(_stubbed(text, (i) => oldText[i] == text[i]))
          ..layout(minWidth: oldWidth, maxWidth: oldWidth);
        _stableLayout = _painter(_stubbed(text, (i) => oldText[i] != text[i]))
          ..layout(minWidth: oldWidth, maxWidth: oldWidth);
      } else {
        _oldLayout = _layout;
        _layout = null; // ownership moved; new layout assigned below
      }
    } else if (hadLayout && _anim == _CounterAnim.fadeOut) {
      // Keep `_layout` as the outgoing glyphs; width stays until end.
    }

    _countWidthOld = _countWidth;
    _increment = count > _currentCount;

    if (count > 0) {
      _countWidth = _measureSlot(text);
      _layout?.dispose();
      _layout = _painter(TextSpan(text: text, style: _textStyle))
        ..layout(minWidth: _countWidth, maxWidth: _countWidth);
    }

    _currentCount = count;
    _currentText = text;

    // Appear overshoot is applied in paint — AnimationController clamps to 1.
    final curve = switch (_anim) {
      _CounterAnim.fadeIn => Curves.linear,
      _ => _defaultCurve,
    };
    _controller.animateTo(1, curve: curve);
    if (mounted) setState(() {});
  }

  double get _displaySlot {
    if (_anim == _CounterAnim.replace && _controller.value < 1) {
      var progressHalf = _controller.value * 2;
      if (progressHalf > 1) progressHalf = 1;
      if (_countWidth == _countWidthOld) return _countWidth;
      return _countWidth * progressHalf + _countWidthOld * (1 - progressHalf);
    }
    if (_anim == _CounterAnim.fadeOut) {
      return _countWidthOld > 0 ? _countWidthOld : _countWidth;
    }
    return _countWidth;
  }

  @override
  Widget build(BuildContext context) {
    final showSeam = _currentCount > 0 || _anim == _CounterAnim.fadeOut;
    if (_displaySlot <= 0 && _anim == _CounterAnim.none) {
      return const SizedBox.shrink();
    }

    final style = _textStyle;

    // Fill the counter strip width. Pill size is painted (lerped), not laid out
    // — host width stays fixed so digit growth (9→10) does not reflow the box.
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final slot = _displaySlot;
        return SizedBox(
          width: double.infinity,
          height: _height,
          child: CustomPaint(
            painter: _SideControlCounterPainter(
              progress: _controller.value,
              anim: _anim,
              increment: _increment,
              textSlot: slot,
              extraWidth: _extraWidth,
              background: _background,
              radius: _radius,
              layout: _layout,
              oldLayout: _oldLayout,
              inLayout: _inLayout,
              stableLayout: _stableLayout,
            ),
            child: showSeam
                ? Center(
                    child: Text(
                      _currentCount > 0 ? '$_currentCount' : _currentText,
                      key: widget.seamKey,
                      style: style.copyWith(color: const Color(0x00000000)),
                    ),
                  )
                : null,
          ),
        );
      },
    );
  }
}

class _SideControlCounterPainter extends CustomPainter {
  _SideControlCounterPainter({
    required this.progress,
    required this.anim,
    required this.increment,
    required this.textSlot,
    required this.extraWidth,
    required this.background,
    required this.radius,
    required this.layout,
    required this.oldLayout,
    required this.inLayout,
    required this.stableLayout,
  });

  final double progress;
  final _CounterAnim anim;
  final bool increment;
  final double textSlot;
  final double extraWidth;
  final Color background;
  final double radius;
  final TextPainter? layout;
  final TextPainter? oldLayout;
  final TextPainter? inLayout;
  final TextPainter? stableLayout;

  static const double _digitSlide = 13;
  static const Curve _easeOut = Cubic(0, 0, 0.58, 1);
  static const Curve _easeIn = Cubic(0.42, 0, 1, 1);

  double get _pillWidth => textSlot + extraWidth;

  Rect _pillRect(Size size) {
    final w = _pillWidth;
    return Rect.fromLTWH((size.width - w) / 2, 0, w, size.height);
  }

  /// Text origin for the lerped slot — CounterDrawable `countLeft`.
  double _textLeft(Size size) => (size.width - textSlot) / 2;

  @override
  void paint(Canvas canvas, Size size) {
    if (anim != _CounterAnim.none && progress < 1) {
      switch (anim) {
        case _CounterAnim.fadeIn:
        case _CounterAnim.fadeOut:
          _paintInOut(canvas, size);
        case _CounterAnim.replace:
          _paintReplace(canvas, size);
        case _CounterAnim.none:
          break;
      }
      return;
    }
    _paintIdle(canvas, size);
  }

  void _paintIdle(Canvas canvas, Size size) {
    final active = layout;
    if (active == null || textSlot <= 0) return;
    final pill = _pillRect(size);
    _drawPill(canvas, pill);
    _paintAt(canvas, size, active, _textLeft(size), 1);
  }

  void _paintInOut(Canvas canvas, Size size) {
    final active = layout;
    if (active == null || textSlot <= 0) return;
    final pill = _pillRect(size);
    final raw = anim == _CounterAnim.fadeIn
        ? const OvershootCurve().transform(progress)
        : (1 - progress);
    final scale = raw.clamp(0.0, 2.0);
    canvas.save();
    canvas.translate(pill.center.dx, pill.center.dy);
    canvas.scale(scale);
    canvas.translate(-pill.center.dx, -pill.center.dy);
    _drawPill(canvas, pill);
    _paintAt(canvas, size, active, _textLeft(size), 1);
    canvas.restore();
  }

  void _paintReplace(Canvas canvas, Size size) {
    if (textSlot <= 0) return;
    var progressHalf = progress * 2;
    if (progressHalf > 1) progressHalf = 1;

    var scale = 1.0;
    if (increment) {
      if (progress <= 0.5) {
        scale += 0.1 * _easeOut.transform(progress * 2);
      } else {
        scale += 0.1 * _easeIn.transform(1 - (progress - 0.5) * 2);
      }
    }

    final pill = _pillRect(size);
    canvas.save();
    canvas.translate(pill.center.dx, pill.center.dy);
    canvas.scale(scale);
    canvas.translate(-pill.center.dx, -pill.center.dy);
    _drawPill(canvas, pill);
    canvas.clipRect(pill);

    final slideIn =
        (increment ? _digitSlide : -_digitSlide) * (1 - progressHalf);
    final slideOut = (increment ? -_digitSlide : _digitSlide) * progressHalf;
    final textLeft = _textLeft(size);

    final incoming = inLayout ?? layout;
    if (incoming != null) {
      _paintAt(canvas, size, incoming, textLeft, progressHalf, dy: slideIn);
    }
    if (oldLayout != null) {
      _paintAt(
        canvas,
        size,
        oldLayout!,
        textLeft,
        1 - progressHalf,
        dy: slideOut,
      );
    }
    if (stableLayout != null) {
      _paintAt(canvas, size, stableLayout!, textLeft, 1);
    }
    canvas.restore();
  }

  void _drawPill(Canvas canvas, Rect pill) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(pill, Radius.circular(radius)),
      Paint()..color = background,
    );
  }

  void _paintAt(
    Canvas canvas,
    Size size,
    TextPainter painter,
    double dx,
    double alpha, {
    double dy = 0,
  }) {
    if (alpha <= 0) return;
    final textDy = (size.height - painter.height) / 2 + dy;
    canvas.saveLayer(
      Offset.zero & size,
      Paint()..color = Color.fromRGBO(255, 255, 255, alpha.clamp(0.0, 1.0)),
    );
    painter.paint(canvas, Offset(dx, textDy));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SideControlCounterPainter old) =>
      progress != old.progress ||
      anim != old.anim ||
      increment != old.increment ||
      textSlot != old.textSlot ||
      extraWidth != old.extraWidth ||
      layout != old.layout ||
      oldLayout != old.oldLayout ||
      inLayout != old.inLayout ||
      stableLayout != old.stableLayout;
}
