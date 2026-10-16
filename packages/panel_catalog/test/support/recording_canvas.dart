import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// One batched atlas draw as the canvas received it.
class AtlasDraw {
  AtlasDraw(this.image, this.transforms, this.rects);

  final ui.Image image;
  final Float32List transforms;
  final Float32List rects;

  int get sprites => rects.length ~/ 4;

  /// Source rectangles, copied so a reused buffer cannot change them later.
  List<Rect> get sources => [
    for (var i = 0; i < rects.length; i += 4)
      Rect.fromLTRB(rects[i], rects[i + 1], rects[i + 2], rects[i + 3]),
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

/// A paragraph and where it was drawn: its top-left and the width it was laid
/// out across.
typedef DrawnParagraph = ({Offset offset, double width});

/// Records what one paint asks of the canvas: what the viewport draws, never
/// render-object fields.
class RecordingCanvas implements Canvas {
  final List<AtlasDraw> atlasDraws = [];
  final List<DrawnCircle> circles = [];
  final List<DrawnRRect> rrects = [];

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
      ),
    );
  }

  @override
  void drawCircle(Offset c, double radius, Paint paint) =>
      circles.add((center: c, radius: radius, color: paint.color));

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
