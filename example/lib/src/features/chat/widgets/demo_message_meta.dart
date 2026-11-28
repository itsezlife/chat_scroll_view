import 'dart:math' as math;

import 'package:chat_scroll_view_example/src/common/widgets/cached_label.dart';
import 'package:chat_scroll_view_example/src/features/chat/outbox/demo_delivery.dart';
import 'package:chat_scroll_view_example/src/features/chat/outbox/demo_status_motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Time (+ optional “edited” + delivery ticks) for the change-transition meta
/// slot. [editedOpacity] is visual only — when [edited] is true the label
/// always occupies layout width so the bubble stays final during morph.
///
/// One render object painting shared, laid-out labels: every row shows a
/// meta, and as a row of labels, spacers and an icon it built about ten
/// elements and hashed three text styles for each row a scroll brought in.
///
/// With a [motion] the status glyph moves between statuses as the
/// platform does (`DemoStatusMotion`): the render object repaints on it, so
/// a frame of motion lays nothing out. At rest it paints exactly what it
/// paints without one.
class DemoMessageMeta extends LeafRenderObjectWidget {
  /// Creates the demo meta row.
  const DemoMessageMeta({
    required this.createdAt,
    required this.color,
    required this.delivery,
    required this.edited,
    this.editedOpacity = 1,
    this.motion,
    super.key,
  });

  /// The status motion the glyph follows; null paints the status at rest.
  final DemoStatusMotion? motion;

  /// Timestamp for the time label.
  final DateTime createdAt;

  /// Meta color.
  final Color color;

  /// The status of the user's own message, null for another's: a clock
  /// while it is on its way, one check once sent, two once read. A failed
  /// message shows no glyph here: the error badge beside the time is its.
  /// The status is also spoken after the time.
  final DemoDelivery? delivery;

  /// When true, show the edited label (subject to [editedOpacity]).
  final bool edited;

  /// Opacity of the “edited” prefix (0→1 during edited-enter).
  final double editedOpacity;

  /// `HH:mm` of [dt] in local time.
  static String formatTime(DateTime dt) {
    final local = dt.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  static const double _editedGap = 4;
  static const double _ticksGap = 3;
  static const double _ticksSize = 14;

  _MetaLabels _labels(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    final style = DefaultTextStyle.of(
      context,
    ).style.merge(TextStyle(color: color, fontSize: 11, height: 1));
    TextPainter label(String text) => CachedLabel.painterFor(
      text,
      style,
      scaler: scaler,
      direction: direction,
    );
    TextPainter glyph(IconData icon) => CachedLabel.painterFor(
      String.fromCharCode(icon.codePoint),
      TextStyle(
        inherit: false,
        color: color,
        // The clock's face fills its box; the checks' strokes do not.
        fontSize: icon == Icons.schedule ? _ticksSize - 2 : _ticksSize,
        fontFamily: icon.fontFamily,
        package: icon.fontPackage,
        height: 1,
        leadingDistribution: TextLeadingDistribution.even,
      ),
      scaler: scaler,
      direction: direction,
    );
    // Every glyph a status shows, so a motion can paint the one it leaves.
    final glyphs = delivery == null
        ? const <DemoDelivery, TextPainter>{}
        : {
            DemoDelivery.sending: glyph(Icons.schedule),
            DemoDelivery.sent: glyph(Icons.done),
            DemoDelivery.read: glyph(Icons.done_all),
          };
    return _MetaLabels(
      direction: direction,
      time: label(formatTime(createdAt)),
      edited: edited ? label('edited') : null,
      status: delivery?.label,
      delivery: delivery,
      glyphs: glyphs,
      color: color,
    );
  }

  @override
  RenderBox createRenderObject(BuildContext context) => _RenderDemoMessageMeta(
    labels: _labels(context),
    editedOpacity: editedOpacity,
    motion: motion,
  );

  @override
  void updateRenderObject(
    BuildContext context,
    // The render object is this widget's own: private with its labels.
    // ignore: library_private_types_in_public_api
    covariant _RenderDemoMessageMeta renderObject,
  ) {
    renderObject
      ..labels = _labels(context)
      ..editedOpacity = editedOpacity
      ..motion = motion;
  }
}

/// The laid-out painters one meta shows.
@immutable
class _MetaLabels {
  const _MetaLabels({
    required this.direction,
    required this.time,
    required this.color,
    this.edited,
    this.status,
    this.delivery,
    this.glyphs = const {},
  });

  final TextDirection direction;
  final TextPainter time;
  final TextPainter? edited;
  final Color color;

  /// The spoken status after the time, or null.
  final String? status;

  /// The status shown; null for another's message.
  final DemoDelivery? delivery;

  /// The glyph of each status, for the user's own message.
  final Map<DemoDelivery, TextPainter> glyphs;

  /// The glyph at rest: none for a failed message (its badge is beside).
  TextPainter? get ticks => glyphs[delivery];

  bool sameAs(_MetaLabels other) =>
      direction == other.direction &&
      identical(time, other.time) &&
      identical(edited, other.edited) &&
      status == other.status &&
      delivery == other.delivery &&
      color == other.color &&
      DemoDelivery.values.every(
        (status) => identical(glyphs[status], other.glyphs[status]),
      );
}

/// Render object of [DemoMessageMeta]: the labels in a row, each centred on
/// its height, ticks in a square box.
class _RenderDemoMessageMeta extends RenderBox {
  _RenderDemoMessageMeta({
    required _MetaLabels labels,
    required double editedOpacity,
    DemoStatusMotion? motion,
  }) : _labels = labels,
       _editedOpacity = editedOpacity.clamp(0.0, 1.0),
       _motion = motion;

  DemoStatusMotion? _motion;
  set motion(DemoStatusMotion? value) {
    if (identical(value, _motion)) return;
    if (attached) _motion?.removeListener(markNeedsPaint);
    _motion = value;
    if (attached) _motion?.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _motion?.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _motion?.removeListener(markNeedsPaint);
    super.detach();
  }

  _MetaLabels _labels;
  set labels(_MetaLabels value) {
    if (value.sameAs(_labels)) return;
    if ((value.edited == null) != (_labels.edited == null)) {
      markNeedsCompositingBitsUpdate();
    }
    _labels = value;
    markNeedsLayout();
    markNeedsSemanticsUpdate();
  }

  double _editedOpacity;
  set editedOpacity(double value) {
    final clamped = value.clamp(0.0, 1.0);
    if (clamped == _editedOpacity) return;
    final shownChanged = (clamped > 0) != (_editedOpacity > 0);
    final fadingChanged = _fading(clamped) != _fading(_editedOpacity);
    _editedOpacity = clamped;
    if (fadingChanged) markNeedsCompositingBitsUpdate();
    markNeedsPaint();
    if (shownChanged) markNeedsSemanticsUpdate();
  }

  /// A part-transparent “edited” paints through an opacity layer.
  static bool _fading(double opacity) => opacity > 0 && opacity < 1;

  @override
  bool get alwaysNeedsCompositing =>
      _labels.edited != null && _fading(_editedOpacity);

  // Left edges in the row's own left-to-right order, set by layout.
  double _editedX = 0;
  double _timeX = 0;
  double _ticksX = 0;

  /// Height of the tallest item: the labels, and the ticks' square box.
  double get _rowHeight => math.max(
    math.max(_labels.time.height, _labels.edited?.height ?? 0),
    _labels.ticks == null ? 0 : DemoMessageMeta._ticksSize,
  );

  double get _rowWidth {
    var width = _labels.time.width;
    if (_labels.edited case final edited?) {
      width += edited.width + DemoMessageMeta._editedGap;
    }
    if (_labels.ticks != null) {
      width += DemoMessageMeta._ticksGap + DemoMessageMeta._ticksSize;
    }
    return width;
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) =>
      constraints.constrain(Size(_rowWidth, _rowHeight));

  @override
  void performLayout() {
    size = computeDryLayout(constraints);
    var x = 0.0;
    if (_labels.edited case final edited?) {
      _editedX = x;
      x += edited.width + DemoMessageMeta._editedGap;
    }
    _timeX = x;
    x += _labels.time.width + DemoMessageMeta._ticksGap;
    _ticksX = x;
  }

  @override
  double computeMinIntrinsicWidth(double height) => _rowWidth;

  @override
  double computeMaxIntrinsicWidth(double height) => _rowWidth;

  @override
  double computeMinIntrinsicHeight(double width) => _rowHeight;

  @override
  double computeMaxIntrinsicHeight(double width) => _rowHeight;

  @override
  bool hitTestSelf(Offset position) => true;

  /// Where an item of [width] whose row-order left edge is [x] paints, with
  /// the row mirrored for right-to-left text.
  double _left(double x, double width) =>
      _labels.direction == TextDirection.ltr ? x : size.width - x - width;

  @override
  void paint(PaintingContext context, Offset offset) {
    final height = size.height;
    void label(Canvas canvas, Offset origin, TextPainter painter, double x) =>
        painter.paint(
          canvas,
          origin +
              Offset(_left(x, painter.width), (height - painter.height) / 2),
        );

    if (_labels.edited case final edited? when _editedOpacity > 0) {
      if (_editedOpacity == 1) {
        label(context.canvas, offset, edited, _editedX);
      } else {
        context.pushOpacity(
          offset,
          (_editedOpacity * 255).round(),
          (context, offset) => label(context.canvas, offset, edited, _editedX),
        );
      }
    }
    label(context.canvas, offset, _labels.time, _timeX);
    if (_labels.delivery != null) {
      const box = DemoMessageMeta._ticksSize;
      _paintStatus(
        context.canvas,
        offset +
            Offset(_left(_ticksX, box) + box / 2, (height - box) / 2 + box / 2),
      );
    }
  }

  // --- Status glyph -----------------------------------------------------------

  // Where the two checks of the double-check glyph sit against the single
  // check's, as fractions of the glyph's size: its front check is the
  // single one moved right, its back check the single one moved left. The
  // slide moves the single check to its back place, so its last frame is
  // the glyph at rest; a fixed distance would end apart from it.
  static const double _frontCheckShift = 2.66 / 24;
  static const double _backCheckShift = 3 / 24;

  /// The status glyph centred on [center]: at rest, or in the motion's
  /// change.
  void _paintStatus(Canvas canvas, Offset center) {
    final glyphs = _labels.glyphs;
    final motion = _motion;
    switch (motion?.transition) {
      case DemoStatusTransition(
        kind: DemoStatusMotionKind.crossFade,
        :final from,
        :final to,
        :final progress,
      ):
        final t = Curves.ease.transform(progress);
        final scaleFrom = motion!.policy.crossFadeScaleFrom;
        _paintGlyph(
          canvas,
          glyphs[from],
          center,
          scale: scaleFrom + (1 - scaleFrom) * (1 - t),
          opacity: 1 - t,
        );
        _paintGlyph(
          canvas,
          glyphs[to],
          center,
          scale: scaleFrom + (1 - scaleFrom) * t,
          opacity: t,
        );
      case DemoStatusTransition(
        kind: DemoStatusMotionKind.checkSlide,
        :final progress,
      ):
        final t = Curves.ease.transform(progress);
        final check = glyphs[DemoDelivery.sent];
        final size = check?.height ?? 0;
        // The single check moves aside; the second is at its place at once.
        _paintGlyph(
          canvas,
          check,
          center.translate(-_backCheckShift * size * t, 0),
        );
        _paintGlyph(
          canvas,
          check,
          center.translate(_frontCheckShift * size, 0),
        );
      case DemoStatusTransition(
        kind: DemoStatusMotionKind.checkPop,
        :final to,
        :final progress,
      ):
        final popFrom = motion!.policy.checkPopFrom;
        _paintGlyph(
          canvas,
          glyphs[to],
          center,
          scale: popFrom + (1 - popFrom) * Curves.easeOut.transform(progress),
        );
      case null:
        if (motion != null &&
            motion.turning &&
            _labels.delivery == DemoDelivery.sending) {
          _paintTurningClock(canvas, center, motion);
        } else {
          _paintGlyph(canvas, _labels.ticks, center);
        }
    }
  }

  void _paintGlyph(
    Canvas canvas,
    TextPainter? glyph,
    Offset center, {
    double scale = 1,
    double opacity = 1,
  }) {
    if (glyph == null || opacity <= 0) return;
    final topLeft = center - Offset(glyph.width / 2, glyph.height / 2);
    if (scale == 1 && opacity >= 1) {
      glyph.paint(canvas, topLeft);
      return;
    }
    canvas
      ..save()
      ..translate(center.dx, center.dy)
      ..scale(scale)
      ..translate(-center.dx, -center.dy);
    if (opacity < 1) {
      canvas.saveLayer(
        Rect.fromCenter(
          center: center,
          width: glyph.width,
          height: glyph.height,
        ).inflate(1),
        Paint()..color = Color.fromRGBO(0, 0, 0, opacity),
      );
      glyph.paint(canvas, topLeft);
      canvas.restore();
    } else {
      glyph.paint(canvas, topLeft);
    }
    canvas.restore();
  }

  // The sending clock drawn in parts, so its frame (with the short hand)
  // and its long hand turn on their own periods.
  void _paintTurningClock(
    Canvas canvas,
    Offset center,
    DemoStatusMotion motion,
  ) {
    const radius = (DemoMessageMeta._ticksSize - 2) * 0.4;
    final stroke = Paint()
      ..color = _labels.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, stroke);
    void hand(double turns, double length) {
      final angle = turns * 2 * math.pi - math.pi / 2;
      canvas.drawLine(
        center,
        center + Offset(math.cos(angle), math.sin(angle)) * length,
        stroke,
      );
    }

    hand(motion.clockTurns, radius * 0.5);
    hand(motion.handTurns, radius * 0.75);
  }

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    final time = _labels.time.plainText;
    final shown = _labels.edited != null && _editedOpacity > 0
        ? 'edited $time'
        : time;
    config
      ..label = switch (_labels.status) {
        final status? => '$shown, $status',
        null => shown,
      }
      ..textDirection = _labels.direction;
  }
}
