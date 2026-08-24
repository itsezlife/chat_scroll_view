/// Shared timing proxy and lean glyph cell for catalog A/B baselines.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Records layout/paint wall time for a baseline scroll subtree.
class BenchmarkTimingWrapper extends SingleChildRenderObjectWidget {
  const BenchmarkTimingWrapper({required super.child, super.key});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderBenchmarkTimingWrapper();
}

/// Proxy that timestamps [performLayout] / [paint] of its child.
class RenderBenchmarkTimingWrapper extends RenderProxyBox {
  /// Last layout duration.
  Duration debugLastLayoutDuration = Duration.zero;

  /// Last paint duration.
  Duration debugLastPaintDuration = Duration.zero;

  @override
  void performLayout() {
    final sw = Stopwatch()..start();
    super.performLayout();
    debugLastLayoutDuration = sw.elapsed;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final sw = Stopwatch()..start();
    super.paint(context, offset);
    debugLastPaintDuration = sw.elapsed;
  }
}

/// Lean glyph cell — Text only (no press ticker / InkWell).
class BaselineGlyphCell extends StatelessWidget {
  const BaselineGlyphCell({
    required this.glyph,
    required this.extent,
    super.key,
  });

  final String glyph;
  final double extent;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: extent,
      height: extent,
      child: Center(
        child: Text(glyph, style: TextStyle(fontSize: extent * 0.55)),
      ),
    );
  }
}
