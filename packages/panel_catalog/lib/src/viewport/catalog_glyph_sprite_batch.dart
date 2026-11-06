import 'dart:collection';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:catalog_assets/catalog_assets.dart' show AtlasSprite;
import 'package:flutter/painting.dart';

/// Collects the sprites of one paint pass and draws each page image's sprites
/// with one batched atlas draw.
///
/// Drawing a sprite per leaf would cost a draw per cell (hundreds per frame);
/// grouped by page it is one draw per page on screen, whatever the number of
/// leaves. [add] only appends to a buffer, [flush] issues the draws and empties
/// the buffers, so the order in which a pass visits leaves does not matter and
/// sprites never overlap (cells do not).
///
/// ## Grouped by image, not by page number
///
/// A baked glyph page and a frame page of an animation are different pictures
/// that can both be page 0, so the number does not name a page here: the
/// [AtlasSprite.page] image does. The batch asks no one what the image belongs
/// to, which keeps it free of every atlas type. Buckets live for one pass (a
/// frame page's image is replaced on each upload, so a bucket kept by image
/// would pile up dead keys); their buffers are recycled, not their keys.
///
/// ## Why raw buffers
///
/// The atlas draw takes its transforms and source rectangles as flat float
/// lists. They are kept per bucket and reused from frame to frame, so a scroll
/// frame allocates nothing per leaf; the lists only grow when a pass draws more
/// sprites of one image than any before it.
///
/// ## Fade
///
/// A sprite added with an `opacity` below 1 makes its bucket draw with a colour
/// per sprite, modulating the page pixels; a bucket without one draws with no
/// colour list at all, so the common opaque pass costs nothing extra.
///
/// A batch never keeps an [AtlasSprite] past [flush]: the page image belongs to
/// the atlas and may be disposed with it, so the batch holds it only between
/// [add] and the [flush] of the same paint pass.
final class CatalogGlyphSpriteBatch {
  /// A baked glyph or a rendered frame is drawn within a modest factor of its
  /// pixel size, so bilinear sampling is enough.
  final Paint _paint = Paint()..filterQuality = FilterQuality.low;

  // The buckets of the pass in progress, in the order their image was first
  // met, and emptied ones waiting to be reused.
  final Map<ui.Image, _PageBatch> _active =
      LinkedHashMap<ui.Image, _PageBatch>.identity();
  final List<_PageBatch> _idle = [];

  /// Queues [sprite] to be drawn with its top-left corner at ([left], [top])
  /// and its pixels scaled by [scale] (destination pixels per page pixel), at
  /// [opacity] of its own.
  void add(
    AtlasSprite sprite, {
    required double left,
    required double top,
    required double scale,
    double opacity = 1,
  }) {
    final batch = _active[sprite.page] ??= _idle.isEmpty
        ? _PageBatch()
        : _idle.removeLast();
    batch.add(sprite, left: left, top: top, scale: scale, opacity: opacity);
  }

  /// Draws every queued sprite, one batched draw per image, and empties the
  /// queue.
  void flush(Canvas canvas) {
    for (final batch in _active.values) {
      batch.flush(canvas, _paint);
    }
    _idle.addAll(_active.values);
    _active.clear();
  }

  /// Drops the buffers and the page handles they point at.
  void dispose() {
    for (final batch in _active.values) {
      batch.clear();
    }
    _active.clear();
    _idle.clear();
  }
}

/// The sprites of one page image queued for one pass.
final class _PageBatch {
  // [scos, ssin, tx, ty] and [left, top, right, bottom] per sprite.
  Float32List _transforms = Float32List(0);
  Float32List _rects = Float32List(0);
  // One packed ARGB per sprite, filled only once a sprite of the pass fades.
  Int32List _colors = Int32List(0);
  int _count = 0;
  bool _faded = false;
  ui.Image? _image;

  void add(
    AtlasSprite sprite, {
    required double left,
    required double top,
    required double scale,
    required double opacity,
  }) {
    if ((_count + 1) * 4 > _transforms.length) {
      _grow();
    }
    _image = sprite.page;
    if (opacity < 1 && !_faded) {
      // Sprites queued before the first fade were opaque: white modulates
      // nothing.
      _faded = true;
      _colors.fillRange(0, _count, _opaque);
    }
    if (_faded) {
      _colors[_count] = Color.fromRGBO(255, 255, 255, opacity).toARGB32();
    }
    final at = _count * 4;
    _transforms[at] = scale;
    _transforms[at + 1] = 0;
    _transforms[at + 2] = left;
    _transforms[at + 3] = top;
    final source = sprite.source;
    _rects[at] = source.left;
    _rects[at + 1] = source.top;
    _rects[at + 2] = source.right;
    _rects[at + 3] = source.bottom;
    _count++;
  }

  void flush(Canvas canvas, Paint paint) {
    final image = _image;
    if (_count == 0 || image == null) {
      clear();
      return;
    }
    // Exact-length views: the draw takes its count from the list length.
    canvas.drawRawAtlas(
      image,
      Float32List.sublistView(_transforms, 0, _count * 4),
      Float32List.sublistView(_rects, 0, _count * 4),
      _faded ? Int32List.sublistView(_colors, 0, _count) : null,
      _faded ? BlendMode.modulate : null,
      null,
      paint,
    );
    clear();
  }

  void clear() {
    _count = 0;
    _faded = false;
    _image = null;
  }

  void _grow() {
    final capacity = _transforms.isEmpty ? 256 * 4 : _transforms.length * 2;
    _transforms = Float32List(capacity)..setRange(0, _count * 4, _transforms);
    _rects = Float32List(capacity)..setRange(0, _count * 4, _rects);
    _colors = Int32List(capacity ~/ 4)..setRange(0, _count, _colors);
  }
}

const int _opaque = 0xFFFFFFFF;
