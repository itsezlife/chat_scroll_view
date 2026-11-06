/// What a paint pass of the panel drew in each cell, as a signature, and the
/// detector that reads a timeline of signatures for a flash.
///
/// A flash is a cell that was drawn and, for a frame, is not (or draws a
/// sprite whose page holds nothing of its own there), then is drawn again. The
/// canvas records the draw calls; the page snapshots of the rig say what a
/// sprite's source rectangle holds.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'video_rig.dart';

/// What a cell showed in one pass.
enum CellKind {
  /// Neither stand-in nor content.
  nothing,

  /// The placeholder shape.
  standIn,

  /// An image draw: a thumbnail or the first-frame still.
  still,

  /// A sprite of a frame page.
  sprite,
}

/// The signature of one cell in one pass.
final class CellSignature {
  const CellSignature(
    this.kind, {
    this.alpha = 1,
    this.probe,
    this.page,
    this.quality,
    this.underAlpha = 0,
  });

  final CellKind kind;

  /// Opacity the content was drawn with.
  final double alpha;

  /// What the page holds under a sprite; null for the other kinds.
  final PixelProbe? probe;

  /// The page image a sprite was drawn from.
  final ui.Image? page;

  /// The filter quality of an image draw.
  final FilterQuality? quality;

  /// The opacity of an image drawn in the cell beneath a sprite: the
  /// thumbnail that stays under content fading in.
  final double underAlpha;

  /// How much of the cell the content covers: a still at its opacity, a sprite
  /// at its opacity when its page holds a pixel there, else nothing.
  double get coverage => switch (kind) {
    CellKind.still => alpha,
    CellKind.sprite =>
      1 - (1 - underAlpha) * (1 - ((probe?.alpha ?? 0) == 0 ? 0 : alpha)),
    _ => 0,
  };

  @override
  String toString() => switch (kind) {
    CellKind.sprite =>
      'sprite(a=${alpha.toStringAsFixed(2)}, '
          '${probe == null || probe!.alpha == 0 ? 'BLANK' : 'clip ${probe!.tag} f${probe!.frame}'}'
          '${underAlpha > 0 ? ', over still ${underAlpha.toStringAsFixed(2)}' : ''})',
    CellKind.still => 'still(a=${alpha.toStringAsFixed(2)}, $quality)',
    _ => kind.name,
  };
}

/// Records one paint pass and reads cells off it.
final class SignatureCanvas implements Canvas {
  SignatureCanvas(this._snapshots);

  final Map<ui.Image, PageSnapshot> _snapshots;

  final List<({ui.Image image, Rect dst, double alpha, FilterQuality q})>
  _images = [];
  final List<({ui.Image image, Rect src, Rect dst, double alpha})> _sprites =
      [];
  final List<Rect> _shapes = [];

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
    for (var i = 0; i < rects.length ~/ 4; i++) {
      final src = Rect.fromLTRB(
        rects[i * 4],
        rects[i * 4 + 1],
        rects[i * 4 + 2],
        rects[i * 4 + 3],
      );
      final scale = rstTransforms[i * 4];
      final left = rstTransforms[i * 4 + 2];
      final top = rstTransforms[i * 4 + 3];
      _sprites.add((
        image: atlas,
        src: src,
        dst: Rect.fromLTWH(left, top, src.width * scale, src.height * scale),
        alpha: colors == null ? 1 : Color(colors[i]).a,
      ));
    }
  }

  @override
  void drawImageRect(ui.Image image, Rect src, Rect dst, Paint paint) =>
      _images.add((
        image: image,
        dst: dst,
        alpha: paint.color.a,
        q: paint.filterQuality,
      ));

  @override
  void drawRRect(RRect rrect, Paint paint) {
    if (paint.color.a > 0 || paint.shader != null) _shapes.add(rrect.outerRect);
  }

  @override
  void drawCircle(Offset c, double radius, Paint paint) {
    if (paint.color.a > 0) {
      _shapes.add(Rect.fromCircle(center: c, radius: radius));
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;

  /// What was drawn inside [cell] (by the centre of the draw).
  CellSignature read(Rect cell) {
    for (final s in _sprites) {
      if (!cell.contains(s.dst.center)) continue;
      // An image in the same cell is drawn before the sprite, which the pass
      // flushes last: it is what the sprite fades in over.
      var under = 0.0;
      for (final i in _images) {
        if (cell.contains(i.dst.center)) under = i.alpha;
      }
      return CellSignature(
        CellKind.sprite,
        alpha: s.alpha,
        probe: _snapshots[s.image]?.probe(s.src),
        page: s.image,
        underAlpha: under,
      );
    }
    for (final i in _images) {
      if (cell.contains(i.dst.center)) {
        return CellSignature(CellKind.still, alpha: i.alpha, quality: i.q);
      }
    }
    for (final r in _shapes) {
      if (cell.contains(r.center)) return const CellSignature(CellKind.standIn);
    }
    return const CellSignature(CellKind.nothing);
  }
}

/// A cell's signature per pass, and the checks on it.
final class CellTimeline {
  CellTimeline(this.label);

  final String label;
  final List<CellSignature> passes = [];

  /// The ways the timeline breaks "placeholder, then still, then animating,
  /// and never less drawn than before".
  List<String> flashes({double tolerance = 0.05, int? ownTag}) {
    final out = <String>[];
    var best = 0.0;
    for (var i = 0; i < passes.length; i++) {
      final s = passes[i];
      if (s.kind == CellKind.sprite) {
        final p = s.probe;
        if (p == null || p.alpha == 0) {
          out.add('$label pass $i: sprite drawn over a BLANK page region');
        } else if (ownTag != null && p.tag != ownTag) {
          out.add(
            '$label pass $i: sprite shows clip ${p.tag}, not clip $ownTag',
          );
        }
      }
      if (best - s.coverage > tolerance) {
        out.add(
          '$label pass $i: coverage fell ${best.toStringAsFixed(2)} -> '
          '${s.coverage.toStringAsFixed(2)} ($s)',
        );
      }
      if (s.coverage > best) best = s.coverage;
    }
    return out;
  }

  /// Run-length view for a report: `still x3, sprite x2, ...`.
  String get compact {
    final buf = StringBuffer();
    String? last;
    var n = 0;
    void flush() {
      if (last != null) buf.write('$last x$n; ');
    }

    for (final s in passes) {
      final text = s.toString();
      if (text == last) {
        n++;
      } else {
        flush();
        last = text;
        n = 1;
      }
    }
    flush();
    return buf.toString();
  }
}
