// Adapted from g1455 0.4.0, lib/src/proxy/proxy_layer_watch.dart.
//
// MIT License
//
// Copyright (c) 2026 Mike Matiunin (PlugFox)
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

/// What changed in a composited subtree since the last look, and where.
///
/// The bound is never tighter than the repaint boundary that holds the
/// change: a repaint mints a new picture inside the boundary that owns it, and
/// its layer carries that boundary's bounds, not the picture's.
@immutable
class GlassLayerChange {
  const GlassLayerChange._({required this.changed, required this.region});

  /// Nothing the watch can see is different.
  static const none = GlassLayerChange._(changed: false, region: null);

  /// Something is different and the watch cannot say where.
  static const everywhere = GlassLayerChange._(changed: true, region: null);

  /// Whether anything at all differs from the last look.
  final bool changed;

  /// Where it differs, in the watched root's space. Null with [changed] true
  /// means anywhere ([everywhere]), or a change that composites no pixel,
  /// which [touches] reports as touching nothing.
  final Rect? region;

  /// Whether the change can have altered a pixel inside [area].
  ///
  /// Inclusive on the edges: a dirty rect of zero area is a real answer, and
  /// `Rect.overlaps` reports false for it against everything.
  bool touches(Rect area) {
    if (!changed) return false;
    if (identical(this, everywhere)) return true;
    final dirty = region;
    if (dirty == null) return false;
    return dirty.right >= area.left &&
        area.right >= dirty.left &&
        dirty.bottom >= area.top &&
        area.bottom >= dirty.top;
  }

  @override
  String toString() => switch ((changed, region)) {
    (false, _) => 'GlassLayerChange.none',
    (true, null) when identical(this, everywhere) =>
      'GlassLayerChange.everywhere',
    (true, final r) => 'GlassLayerChange(${r ?? 'nothing composited'})',
  };
}

/// Watches the composited layer tree of one subtree for change, so a capture
/// of it is redone only when something under the captured region changed.
///
/// The render tree cannot be watched from above: a repaint boundary repaints
/// without its ancestors. The layer tree cannot hide one: a repaint mints a
/// new `PictureLayer` and `ui.Picture` inside the boundary that owns it, and a
/// change that repaints nothing (an opacity, an offset, a clip) changes a
/// property of a retained layer, which is read here.
///
/// The table of layer types is a whitelist. A type this file does not read
/// (a platform view's layer, a follower whose geometry belongs to a leader
/// elsewhere, a subclass of a read type, anything newer than this file)
/// reports a change on every look, anywhere. A `TextureLayer`, whose pixels
/// arrive from outside Dart, reports a change on every look too, bounded by
/// its rect. Not knowing costs a capture, never a stale one.
///
/// What it may miss: pixels a picture draws outside its layer's canvas bounds
/// (a render object painting past its repaint boundary's paint bounds).
class GlassLayerWatch {
  List<Object?>? _previous;
  List<Rect?>? _previousBounds;

  /// Whether the subtree under [root] composites differently than at the last
  /// call, and where, in [root]'s own space (its offset is not applied). The
  /// first call, and the first after [reset], reports [GlassLayerChange.everywhere].
  GlassLayerChange changeSince(ContainerLayer root) {
    final walk = _Walk()..visit(root, Matrix4.identity(), null, isRoot: true);
    final current = walk.out;
    final currentBounds = walk.bounds;
    final previous = _previous;
    final previousBounds = _previousBounds;
    _previous = current;
    _previousBounds = currentBounds;
    if (previous == null ||
        previousBounds == null ||
        previous.length != current.length) {
      return GlassLayerChange.everywhere;
    }
    Rect? dirty;
    var changed = false;
    for (var i = 0; i < current.length; i++) {
      if (current[i] == previous[i]) continue;
      changed = true;
      final before = previousBounds[i];
      final after = currentBounds[i];
      // The entry that left and the one that arrived, both: a subtree that
      // moved changed only the offset above it, and the pixels it vacated
      // are as dirty as the ones it took.
      if (identical(before, _Walk.anywhere) ||
          identical(after, _Walk.anywhere)) {
        return GlassLayerChange.everywhere;
      }
      dirty = _Walk.union(_Walk.union(dirty, before), after);
    }
    if (!changed) return GlassLayerChange.none;
    return GlassLayerChange._(changed: true, region: dirty);
  }

  /// Forgets the last look, so the next call reports a change.
  void reset() {
    _previous = null;
    _previousBounds = null;
  }

  /// Structure marker: moving a subtree between parents is visible even when
  /// every layer in it is unchanged.
  static final Object _pop = Object();

  // Matched by exact type: a subclass can override `addToScene` and push
  // state of its own, which `is` would describe by its parent's properties.
  static const Set<Type> _exact = <Type>{
    PictureLayer,
    TextureLayer,
    ContainerLayer,
    OffsetLayer,
    OpacityLayer,
    ImageFilterLayer,
    TransformLayer,
    ClipRectLayer,
    ClipRRectLayer,
    ClipRSuperellipseLayer,
    ClipPathLayer,
    ColorFilterLayer,
    ShaderMaskLayer,
    BackdropFilterLayer,
    LeaderLayer,
  };

  // `AnnotatedRegionLayer` is generic, so its runtime type is an
  // instantiation the set cannot name; it composites nothing of its own.
  static bool _readable(Layer layer) =>
      _exact.contains(layer.runtimeType) || layer is AnnotatedRegionLayer;

  // Ordered subclass first: three read types are `OffsetLayer`s.
  static void _describeSelf(Layer layer, List<Object?> out) {
    if (!_readable(layer)) {
      // A fresh object never equals last look's: changing on every look.
      out.add(Object());
      return;
    }
    switch (layer) {
      case PictureLayer(:final picture):
        // A repaint always replaces the picture.
        out.add(picture);
      case TextureLayer():
        // Its pixels change outside Dart, with no layer change to read.
        out.add(Object());
      case OpacityLayer(:final alpha, :final offset):
        out
          ..add(alpha)
          ..add(offset);
      case ImageFilterLayer(:final imageFilter, :final offset):
        out
          ..add(imageFilter)
          ..add(offset);
      case TransformLayer(:final transform, :final offset):
        // A copy: a render object may mutate the matrix it handed the layer.
        out
          ..add(switch (transform) {
            final t? => Matrix4.copy(t),
            null => null,
          })
          ..add(offset);
      case OffsetLayer(:final offset):
        out.add(offset);
      case ClipRectLayer(:final clipRect, :final clipBehavior):
        out
          ..add(clipRect)
          ..add(clipBehavior);
      case ClipRRectLayer(:final clipRRect, :final clipBehavior):
        out
          ..add(clipRRect)
          ..add(clipBehavior);
      case ClipRSuperellipseLayer(
        :final clipRSuperellipse,
        :final clipBehavior,
      ):
        out
          ..add(clipRSuperellipse)
          ..add(clipBehavior);
      case ClipPathLayer(:final clipPath, :final clipBehavior):
        // By identity: `Path` has no equality, and a clipper that changes its
        // mind goes through a repaint, which hands the layer a new path.
        out
          ..add(clipPath)
          ..add(clipBehavior);
      case ColorFilterLayer(:final colorFilter):
        out.add(colorFilter);
      case ShaderMaskLayer(:final shader, :final maskRect, :final blendMode):
        out
          ..add(shader)
          ..add(maskRect)
          ..add(blendMode);
      case BackdropFilterLayer(
        :final filter,
        :final blendMode,
        :final backdropKey,
      ):
        out
          ..add(filter)
          ..add(blendMode)
          ..add(backdropKey);
      case LeaderLayer(:final link, :final offset):
        out
          ..add(link)
          ..add(offset);
      case AnnotatedRegionLayer() || ContainerLayer():
        // Nothing of its own reaches a pixel.
        break;
      default:
        // Unreachable unless the set and the cases drift apart.
        out.add(Object());
    }
  }
}

/// One pass over the composited tree: the signature, and next to each entry
/// the root-space bounds of what it composites. A null bound composites
/// nothing; [anywhere] could be anywhere.
class _Walk {
  final out = <Object?>[];
  final bounds = <Rect?>[];

  /// Compared by identity, so a real rect equal to it cannot impersonate it.
  /// Not const for the same reason: a const rect of the same values would be
  /// this very object.
  // ignore: prefer_const_constructors
  static final Rect anywhere = Rect.fromLTRB(
    -double.maxFinite,
    -double.maxFinite,
    double.maxFinite,
    double.maxFinite,
  );

  static Rect? union(Rect? a, Rect? b) {
    if (a == null) return b;
    if (b == null) return a;
    if (identical(a, anywhere) || identical(b, anywhere)) return anywhere;
    return a.expandToInclude(b);
  }

  static Rect? _map(Rect rect, Matrix4 toRoot, Rect? clip) {
    final mapped = MatrixUtils.transformRect(toRoot, rect);
    if (clip == null) return mapped.isEmpty ? null : mapped;
    final inside = mapped.intersect(clip);
    return inside.isEmpty ? null : inside;
  }

  // Never null: null means unclipped here, so a clip entirely outside the one
  // above it must stay an empty clip, not become none.
  static Rect _narrow(Rect local, Matrix4 toRoot, Rect? clip) =>
      _map(local, toRoot, clip) ?? Rect.zero;

  static Matrix4 _translated(Matrix4 toRoot, Offset offset) =>
      Matrix4.copy(toRoot)..translateByDouble(offset.dx, offset.dy, 0, 1);

  /// Walks [layer], appending its entries; returns what it composites.
  Rect? visit(Layer layer, Matrix4 toRoot, Rect? clip, {required bool isRoot}) {
    final start = out.length;
    out.add(layer.runtimeType);
    GlassLayerWatch._describeSelf(layer, out);
    final selfEnd = out.length;
    while (bounds.length < selfEnd) {
      bounds.add(null);
    }

    var childTransform = toRoot;
    var childClip = clip;
    Rect? own;
    // Paints outside what its children cover by an amount Dart cannot read (a
    // filter, an unread type): answers with the clip above it.
    var spreads = false;
    // Can paint all of its clip on its own account (a colour filter that
    // does not keep transparent black transparent).
    var fills = false;

    if (!GlassLayerWatch._readable(layer)) {
      spreads = true;
    } else {
      switch (layer) {
        case PictureLayer(:final canvasBounds):
          own = _map(canvasBounds, toRoot, clip);
        case TextureLayer(:final rect):
          own = _map(rect, toRoot, clip);
        case TransformLayer(:final transform?, :final offset):
          // `translate(offset) * transform`, as `TransformLayer.addToScene`
          // hands it to the engine.
          childTransform = _translated(toRoot, offset)..multiply(transform);
        case ImageFilterLayer():
          spreads = true;
        case OffsetLayer(:final offset):
          if (!isRoot && offset != Offset.zero) {
            childTransform = _translated(toRoot, offset);
          }
        case ClipRectLayer(:final clipRect?):
          childClip = _narrow(clipRect, toRoot, clip);
        case ClipRRectLayer(:final clipRRect?):
          childClip = _narrow(clipRRect.outerRect, toRoot, clip);
        case ClipRSuperellipseLayer(:final clipRSuperellipse?):
          childClip = _narrow(clipRSuperellipse.outerRect, toRoot, clip);
        case ClipPathLayer(:final clipPath?):
          childClip = _narrow(clipPath.getBounds(), toRoot, clip);
        case BackdropFilterLayer():
          // Filters what is behind it over its whole clip; anything it pulls
          // in from outside changed somewhere with an entry of its own.
          spreads = true;
        case ColorFilterLayer():
          // A changed filter can change every pixel of its clip; what its
          // children change stays where they changed it.
          fills = true;
        case LeaderLayer(:final offset) when offset != Offset.zero:
          childTransform = _translated(toRoot, offset);
        default:
          break;
      }
    }

    var subtree = own;
    if (layer case final ContainerLayer container) {
      for (
        var child = container.firstChild;
        child != null;
        child = child.nextSibling
      ) {
        subtree = union(
          subtree,
          visit(child, childTransform, childClip, isRoot: false),
        );
      }
    }
    if (spreads || fills) {
      subtree = switch (childClip) {
        null => anywhere,
        final c when c.isEmpty => null,
        final c => c,
      };
    }
    out.add(GlassLayerWatch._pop);
    bounds.add(null);
    // A container's own entries answer for its whole subtree (its offset puts
    // the subtree where it is); a layer that spreads patches its descendants
    // too, or a blurred repaint would read as dirty only where it repainted.
    final end = spreads ? out.length : selfEnd;
    for (var i = start; i < end; i++) {
      bounds[i] = subtree;
    }
    return subtree;
  }
}
