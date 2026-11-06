import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// One batched atlas draw as the canvas received it.
class AtlasDraw {
  AtlasDraw(
    this.image,
    this.transforms,
    this.rects, {
    this.colors,
    this.blendMode,
  });

  final ui.Image image;
  final Float32List transforms;
  final Float32List rects;

  /// Per-sprite colours, null when the draw tinted nothing.
  final Int32List? colors;
  final BlendMode? blendMode;

  int get sprites => rects.length ~/ 4;

  /// Source rectangles, copied so a reused buffer cannot change them later.
  List<Rect> get sources => [
    for (var i = 0; i < rects.length; i += 4)
      Rect.fromLTRB(rects[i], rects[i + 1], rects[i + 2], rects[i + 3]),
  ];

  /// Where each sprite's top-left corner lands (`tx`, `ty`).
  List<Offset> get offsets => [
    for (var i = 0; i < transforms.length; i += 4)
      Offset(transforms[i + 2], transforms[i + 3]),
  ];

  /// Scale of each sprite's transform (`scos`).
  List<double> get scales => [
    for (var i = 0; i < transforms.length; i += 4) transforms[i],
  ];
}

/// A rounded rect and the paint it was filled with, as drawn.
typedef DrawnRRect = ({RRect rrect, Color color, ui.Shader? shader});

/// A circle and the colour it was filled with, as drawn.
typedef DrawnCircle = ({Offset center, double radius, Color color});

/// An arc and where it started and how far it swept, in radians.
typedef DrawnArc = ({Rect rect, double start, double sweep, Color color});

/// A paragraph and where it was drawn: its top-left and the width it was laid
/// out across.
typedef DrawnParagraph = ({Offset offset, double width});

/// Records what one paint asks of the canvas: what the viewport draws, never
/// render-object fields.
class RecordingCanvas implements Canvas {
  final List<AtlasDraw> atlasDraws = [];

  /// Every `drawImageRect` and `drawImage`: what a paintable that paints itself
  /// asks of the canvas.
  int imageDraws = 0;
  final List<DrawnCircle> circles = [];
  final List<DrawnRRect> rrects = [];
  final List<DrawnArc> arcs = [];

  /// Draw calls of the kinds above that matter for stacking, in the order the
  /// canvas received them: `'rrect'` and `'atlas'`.
  final List<String> ops = [];
  final List<DrawnParagraph> paragraphDraws = [];
  int get paragraphs => paragraphDraws.length;
  int saves = 0;

  @override
  void drawRawAtlas(
    ui.Image atlas,
    Float32List rstTransforms,
    Float32List rects,
    Int32List? colors,
    BlendMode? blendMode,
    Rect? cullRect,
    Paint paint,
  ) {
    ops.add('atlas');
    atlasDraws.add(
      AtlasDraw(
        atlas,
        Float32List.fromList(rstTransforms),
        Float32List.fromList(rects),
        colors: colors == null ? null : Int32List.fromList(colors),
        blendMode: blendMode,
      ),
    );
  }

  @override
  void drawImageRect(ui.Image image, Rect src, Rect dst, Paint paint) =>
      imageDraws++;

  @override
  void drawCircle(Offset c, double radius, Paint paint) =>
      circles.add((center: c, radius: radius, color: paint.color));

  @override
  void drawArc(
    Rect rect,
    double startAngle,
    double sweepAngle,
    bool useCenter,
    Paint paint,
  ) => arcs.add((
    rect: rect,
    start: startAngle,
    sweep: sweepAngle,
    color: paint.color,
  ));

  @override
  void drawParagraph(ui.Paragraph paragraph, Offset offset) =>
      paragraphDraws.add((offset: offset, width: paragraph.width));

  // The paint is copied at the draw call, as the real canvas does: the painter
  // reuses its paints.
  @override
  void drawRRect(RRect rrect, Paint paint) {
    ops.add('rrect');
    rrects.add((rrect: rrect, color: paint.color, shader: paint.shader));
  }

  @override
  void save() => saves++;

  /// The factors of every `scale` call, in order.
  final List<double> scaleCalls = [];

  @override
  void scale(double sx, [double? sy]) => scaleCalls.add(sx);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
