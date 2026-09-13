import 'dart:math' as math;
import 'dart:ui';

/// Turn orientation of a perimeter vertex corner along a clockwise polygon.
enum ChatCornerOrientation {
  /// Clockwise outer turn (positive cross product in screen coordinates).
  convex,

  /// Counter-clockwise inner turn (negative cross product in screen coordinates).
  reflex,

  /// Collinear vectors (near-zero cross product).
  collinear,
}

/// Structured geometry for a rounded polygon corner.
typedef _CornerVertex = ({
  Offset entry,
  Offset exit,
  double radius,
  ChatCornerOrientation orientation,
});

/// Pure geometry engine that converts multiline text bounding boxes into a
/// single, continuous, closed [Path] with smooth vector-rounded corners.
///
/// Converts a list of text line [Rect] bounds into unified contours featuring:
/// - Smooth 4-corner rounded rectangles for single-line spans.
/// - Vector-rounded outer convex corners and inner reflex corners for
///   multi-line wrapped text (such as hyperlinks or code spans).
/// - Collinear vertex elimination along straight runs.
/// - Dynamic corner radius clamping to half the minimum adjoining edge length,
///   preventing self-intersections or visual artifacts on small steps.
/// - Automatic partitioning of vertically or horizontally disconnected lines
///   into distinct closed sub-paths.
///
/// Reused across tap highlight ripples and text selection plates.
abstract final class ChatSmoothContour {
  /// Default contour rounding radius in logical pixels (4 dp).
  static const double defaultRadius = 4;

  /// Tolerance in logical pixels for considering consecutive lines vertically contiguous.
  static const double _verticalContiguityTolerance = 4;

  /// Builds a single closed, continuous vector-rounded [Path] from [boxes].
  ///
  /// Empty or degenerate (zero-area) rects in [boxes] are filtered out. If no
  /// valid boxes remain, an empty [Path] is returned.
  ///
  /// Corner radius [radius] defaults to [defaultRadius]. If [radius] is zero or
  /// negative, the path is generated with sharp rectilinear corners.
  static Path buildPath(
    List<Rect> boxes, {
    double radius = defaultRadius,
  }) {
    if (boxes.isEmpty) return Path();

    // 1. Filter out empty or non-positive dimension boxes
    final validBoxes = boxes.where((b) => b.width > 0 && b.height > 0).toList();
    if (validBoxes.isEmpty) return Path();

    final effectiveRadius = radius < 0 ? 0.0 : radius;

    // 2. Sort by vertical top position, then horizontal left
    final sorted = List<Rect>.from(validBoxes)
      ..sort((a, b) {
        final topDiff = a.top.compareTo(b.top);
        if (topDiff != 0) return topDiff;
        return a.left.compareTo(b.left);
      });

    // 3. Merge overlapping or touching boxes on the same visual line
    final mergedLines = <Rect>[];
    for (final box in sorted) {
      if (mergedLines.isEmpty) {
        mergedLines.add(box);
        continue;
      }

      final last = mergedLines.last;
      final verticalOverlap = math.min(last.bottom, box.bottom) - math.max(last.top, box.top);
      final isSameLine = verticalOverlap > 0.5 * math.min(last.height, box.height) ||
          ((last.top - box.top).abs() <= 2 && (last.bottom - box.bottom).abs() <= 2);

      if (isSameLine && box.left <= last.right + 2) {
        mergedLines[mergedLines.length - 1] = last.expandToInclude(box);
      } else {
        mergedLines.add(box);
      }
    }

    // 4. Partition lines into contiguous clusters (connected components)
    final clusters = <List<Rect>>[];
    var currentCluster = <Rect>[];

    for (final line in mergedLines) {
      if (currentCluster.isEmpty) {
        currentCluster.add(line);
        continue;
      }

      final prev = currentCluster.last;
      final verticalGap = line.top - prev.bottom;
      final horizontalOverlap =
          math.max(prev.left, line.left) < math.min(prev.right, line.right);

      if (verticalGap <= _verticalContiguityTolerance && horizontalOverlap) {
        currentCluster.add(line);
      } else {
        clusters.add(currentCluster);
        currentCluster = [line];
      }
    }
    if (currentCluster.isNotEmpty) {
      clusters.add(currentCluster);
    }

    final resultPath = Path();

    // 5. Build contours for each cluster
    for (final cluster in clusters) {
      if (cluster.length == 1) {
        final rect = cluster.first;
        if (effectiveRadius <= 0) {
          resultPath.addRect(rect);
        } else {
          final r = math.min(effectiveRadius, math.min(rect.width / 2, rect.height / 2));
          resultPath.addRRect(RRect.fromRectAndRadius(rect, Radius.circular(r)));
        }
      } else {
        _buildMultilineContour(resultPath, cluster, effectiveRadius);
      }
    }

    return resultPath;
  }

  /// Computes the 2D cross product (determinant) of incoming vector [u]
  /// and outgoing vector [v]: `u.dx * v.dy - u.dy * v.dx`.
  ///
  /// In Flutter screen coordinates (X right, Y down):
  /// - `> 0`: clockwise turn (convex outer corner).
  /// - `< 0`: counter-clockwise turn (reflex inner corner).
  /// - `== 0`: collinear vectors.
  static double crossProduct(Offset u, Offset v) => u.dx * v.dy - u.dy * v.dx;

  /// Classifies the turn orientation of incoming vector [u] and outgoing vector [v].
  static ChatCornerOrientation cornerOrientation(Offset u, Offset v) {
    final det = crossProduct(u, v);
    if (det.abs() < 1e-6) return ChatCornerOrientation.collinear;
    return det > 0 ? ChatCornerOrientation.convex : ChatCornerOrientation.reflex;
  }

  /// Generates a single closed smooth contour for a cluster of [N >= 2] connected lines.
  static void _buildMultilineContour(Path path, List<Rect> lines, double radius) {
    final lineCount = lines.length;

    // Harmonize seam vertical coordinates between consecutive lines
    final seams = List<double>.filled(lineCount + 1, 0);
    seams[0] = lines[0].top;
    for (var i = 1; i < lineCount; i++) {
      seams[i] = (lines[i - 1].bottom + lines[i].top) / 2;
    }
    seams[lineCount] = lines[lineCount - 1].bottom;

    final rawVertices = <Offset>[];

    // 1. Top edge of line 0
    rawVertices.add(Offset(lines[0].left, seams[0]));
    rawVertices.add(Offset(lines[0].right, seams[0]));

    // 2. Right transitions going down
    for (var i = 0; i < lineCount - 1; i++) {
      final currRight = lines[i].right;
      final nextRight = lines[i + 1].right;
      final seamY = seams[i + 1];

      rawVertices.add(Offset(currRight, seamY));
      if ((currRight - nextRight).abs() > 1e-4) {
        rawVertices.add(Offset(nextRight, seamY));
      }
    }

    // 3. Bottom edge of last line
    rawVertices.add(Offset(lines[lineCount - 1].right, seams[lineCount]));
    rawVertices.add(Offset(lines[lineCount - 1].left, seams[lineCount]));

    // 4. Left transitions going up
    for (var i = lineCount - 1; i > 0; i--) {
      final currLeft = lines[i].left;
      final nextLeft = lines[i - 1].left;
      final seamY = seams[i];

      rawVertices.add(Offset(currLeft, seamY));
      if ((currLeft - nextLeft).abs() > 1e-4) {
        rawVertices.add(Offset(nextLeft, seamY));
      }
    }

    // Deduplicate consecutive identical vertices
    final deduped = <Offset>[];
    for (final v in rawVertices) {
      if (deduped.isEmpty || (v - deduped.last).distanceSquared > 1e-6) {
        deduped.add(v);
      }
    }
    if (deduped.length > 1 && (deduped.first - deduped.last).distanceSquared < 1e-6) {
      deduped.removeLast();
    }

    // Collinear vertex elimination
    var vertices = deduped;
    var changed = true;
    while (changed && vertices.length > 2) {
      changed = false;
      final filtered = <Offset>[];
      final n = vertices.length;
      for (var i = 0; i < n; i++) {
        final prev = vertices[(i - 1 + n) % n];
        final curr = vertices[i];
        final next = vertices[(i + 1) % n];

        final u = curr - prev;
        final v = next - curr;

        final cross = crossProduct(u, v);
        final dot = u.dx * v.dx + u.dy * v.dy;

        if (cross.abs() < 1e-6 && dot > 0) {
          changed = true; // Collinear point eliminated
        } else {
          filtered.add(curr);
        }
      }
      vertices = filtered;
    }

    final vertexCount = vertices.length;
    if (vertexCount < 3) return;

    if (radius <= 0) {
      // Sharp rectilinear polygon
      path.moveTo(vertices[0].dx, vertices[0].dy);
      for (var i = 1; i < vertexCount; i++) {
        path.lineTo(vertices[i].dx, vertices[i].dy);
      }
      path.close();
      return;
    }

    // Compute entry, exit, turn orientation, and clamped radius for each vertex
    final corners = <_CornerVertex>[];

    for (var i = 0; i < vertexCount; i++) {
      final prev = vertices[(i - 1 + vertexCount) % vertexCount];
      final curr = vertices[i];
      final next = vertices[(i + 1) % vertexCount];

      final u = curr - prev;
      final v = next - curr;

      final inLen = u.distance;
      final outLen = v.distance;

      final uHat = inLen > 1e-6 ? Offset(u.dx / inLen, u.dy / inLen) : Offset.zero;
      final vHat = outLen > 1e-6 ? Offset(v.dx / outLen, v.dy / outLen) : Offset.zero;

      final orientation = cornerOrientation(u, v);
      final minAdjoiningEdgeHalf = math.min(inLen / 2, outLen / 2);
      final clampedRadius = radius < 0 ? 0.0 : math.min(radius, minAdjoiningEdgeHalf);

      corners.add((
        entry: curr - Offset(uHat.dx * clampedRadius, uHat.dy * clampedRadius),
        exit: curr + Offset(vHat.dx * clampedRadius, vHat.dy * clampedRadius),
        radius: clampedRadius,
        orientation: orientation,
      ));
    }

    // Construct the rounded path seamlessly
    path.moveTo(corners[0].exit.dx, corners[0].exit.dy);

    for (var i = 1; i <= vertexCount; i++) {
      final corner = corners[i % vertexCount];
      path.lineTo(corner.entry.dx, corner.entry.dy);
      if (corner.radius > 1e-4) {
        path.arcToPoint(
          corner.exit,
          radius: Radius.circular(corner.radius),
          clockwise: corner.orientation == ChatCornerOrientation.convex,
        );
      } else {
        path.lineTo(corner.exit.dx, corner.exit.dy);
      }
    }
    path.close();
  }
}
