import 'dart:math' as math;

import 'package:chat_scroll_view_example/src/common/widgets/cached_label.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Time (+ optional “edited” + delivery ticks) for the change-transition meta
/// slot. [editedOpacity] is visual only — when [edited] is true the label
/// always occupies layout width so the bubble stays final during morph.
///
/// One render object painting shared, laid-out labels: every row shows a
/// meta, and as a row of labels, spacers and an icon it built about ten
/// elements and hashed three text styles for each row a scroll brought in.
class DemoMessageMeta extends LeafRenderObjectWidget {
  /// Creates the demo meta row.
  const DemoMessageMeta({
    required this.createdAt,
    required this.color,
    required this.showStatus,
    required this.edited,
    this.editedOpacity = 1,
    super.key,
  });

  /// Timestamp for the time label.
  final DateTime createdAt;

  /// Meta color.
  final Color color;

  /// When true, show outgoing delivery ticks.
  final bool showStatus;

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
    return _MetaLabels(
      direction: direction,
      time: label(formatTime(createdAt)),
      edited: edited ? label('edited') : null,
      ticks: showStatus
          ? CachedLabel.painterFor(
              String.fromCharCode(Icons.done_all.codePoint),
              TextStyle(
                inherit: false,
                color: color,
                fontSize: _ticksSize,
                fontFamily: Icons.done_all.fontFamily,
                package: Icons.done_all.fontPackage,
                height: 1,
                leadingDistribution: TextLeadingDistribution.even,
              ),
              scaler: scaler,
              direction: direction,
            )
          : null,
    );
  }

  @override
  RenderBox createRenderObject(BuildContext context) => _RenderDemoMessageMeta(
    labels: _labels(context),
    editedOpacity: editedOpacity,
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
      ..editedOpacity = editedOpacity;
  }
}

/// The laid-out painters one meta shows.
@immutable
class _MetaLabels {
  const _MetaLabels({
    required this.direction,
    required this.time,
    this.edited,
    this.ticks,
  });

  final TextDirection direction;
  final TextPainter time;
  final TextPainter? edited;
  final TextPainter? ticks;

  bool sameAs(_MetaLabels other) =>
      direction == other.direction &&
      identical(time, other.time) &&
      identical(edited, other.edited) &&
      identical(ticks, other.ticks);
}

/// Render object of [DemoMessageMeta]: the labels in a row, each centred on
/// its height, ticks in a square box.
class _RenderDemoMessageMeta extends RenderBox {
  _RenderDemoMessageMeta({
    required _MetaLabels labels,
    required double editedOpacity,
  }) : _labels = labels,
       _editedOpacity = editedOpacity.clamp(0.0, 1.0);

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
    if (_labels.ticks case final ticks?) {
      const box = DemoMessageMeta._ticksSize;
      ticks.paint(
        context.canvas,
        offset +
            Offset(
              _left(_ticksX, box) + (box - ticks.width) / 2,
              (height - box) / 2 + (box - ticks.height) / 2,
            ),
      );
    }
  }

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    final time = _labels.time.plainText;
    config
      ..label = _labels.edited != null && _editedOpacity > 0
          ? 'edited $time'
          : time
      ..textDirection = _labels.direction;
  }
}
