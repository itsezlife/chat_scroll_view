import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:catalog_assets/glyph_atlas.dart';
import 'package:flutter/painting.dart';

/// Collects the baked glyphs of one paint pass and draws each atlas page's
/// sprites with one batched atlas draw.
///
/// Drawing a sprite per leaf would cost a draw per cell (hundreds per frame);
/// grouped by page it is one draw per page on screen, whatever the number of
/// leaves. [add] only appends to a buffer, [flush] issues the draws and empties
/// the buffers, so the order in which a pass visits leaves does not matter and
/// sprites never overlap (cells do not).
///
/// ## Why raw buffers
///
/// The atlas draw takes its transforms and source rectangles as flat float
/// lists. They are kept per page and reused from frame to frame, so a scroll
/// frame allocates nothing per leaf; the lists only grow when a pass draws more
/// sprites of one page than any before it.
///
/// A batch never keeps an [AtlasSprite] past [flush]: the page image belongs to
/// the atlas and may be disposed with it, so the batch holds it only between
/// [add] and the [flush] of the same paint pass.
final class CatalogGlyphSpriteBatch {
  /// A baked glyph is drawn within a modest factor of its baked size, so
  /// bilinear sampling is enough.
  final Paint _paint = Paint()..filterQuality = FilterQuality.low;

  // One bucket per page; buckets are kept (emptied) between passes.
  final Map<int, _PageBatch> _pages = <int, _PageBatch>{};

  /// Queues [sprite] to be drawn with its top-left corner at ([left], [top])
  /// and its pixels scaled by [scale] (destination pixels per page pixel).
  void add(
    AtlasSprite sprite, {
    required double left,
    required double top,
    required double scale,
  }) {
    final batch = _pages[sprite.pageIndex] ??= _PageBatch();
    batch.add(sprite, left: left, top: top, scale: scale);
  }

  /// Draws every queued sprite, one batched draw per page, and empties the
  /// queue.
  void flush(Canvas canvas) {
    for (final batch in _pages.values) {
      batch.flush(canvas, _paint);
    }
  }

  /// Drops the buffers and the page handles they point at.
  void dispose() {
    for (final batch in _pages.values) {
      batch.clear();
    }
    _pages.clear();
  }
}

/// The sprites of one page queued for one pass.
final class _PageBatch {
  // [scos, ssin, tx, ty] and [left, top, right, bottom] per sprite.
  Float32List _transforms = Float32List(0);
  Float32List _rects = Float32List(0);
  int _count = 0;
  ui.Image? _image;

  void add(
    AtlasSprite sprite, {
    required double left,
    required double top,
    required double scale,
  }) {
    if ((_count + 1) * 4 > _transforms.length) {
      _grow();
    }
    // Every sprite of a page shares one image; the latest one wins if a page
    // were ever replaced mid-pass, and it is the live one.
    _image = sprite.page;
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
      null,
      null,
      null,
      paint,
    );
    clear();
  }

  void clear() {
    _count = 0;
    _image = null;
  }

  void _grow() {
    final capacity = _transforms.isEmpty ? 256 * 4 : _transforms.length * 2;
    _transforms = Float32List(capacity)..setRange(0, _count * 4, _transforms);
    _rects = Float32List(capacity)..setRange(0, _count * 4, _rects);
  }
}
