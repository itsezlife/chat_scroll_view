import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/painting.dart';
import 'package:panel_catalog/panel_catalog_diagnostics.dart';
import 'package:panel_catalog/src/model/catalog_glyph_box.dart'
    show kCirclePlaceholderRadiusFactor;
import 'package:panel_catalog/src/model/catalog_leaf.dart';
import 'package:panel_catalog/src/viewport/catalog_glyph_sprite_batch.dart';
import 'package:panel_catalog/src/viewport/catalog_leaf_binding_pool.dart';
import 'package:panel_catalog/src/viewport/catalog_leaf_paint_theme.dart';
import 'package:panel_catalog/src/viewport/catalog_paragraph_cache.dart';
import 'package:panel_catalog/src/viewport/catalog_slot_projection.dart';

/// Most section-header paragraphs one painter keeps; a header is keyed by title,
/// style and layout width, so a resize adds one per visible header per step.
/// Far above the headers of one screen (a handful).
const int kHeaderParagraphCacheLimit = 64;

/// Paints catalog headers and leaves onto a [Canvas].
///
/// Owns a bounded paragraph cache for section titles so repeated paint of the
/// same visible band does not rebuild text layouts every frame. Does **not**
/// own layout slots, scroll offset or the asset cache: the render object
/// passes content [origin], slot geometry, the leaf's [CatalogBoundLeaf] and
/// [CatalogLeafPaintTheme].
///
/// ## Coordinate contract
///
/// [origin] is the paint origin of content-y `0` after scroll translation
/// (`paintOffset.translate(0, -scrollOffset)`). A slot at content-y `top` is
/// drawn at `origin.dy + top`. Callers MUST clip to the viewport before
/// invoking paint methods if overdraw outside the viewport is unwanted.
///
/// ## A pass
///
/// [beginPass] opens a paint pass and [endPass] closes it: sprites queued by
/// [paintLeaf] are drawn at the end, and the pass reports whether anything
/// drawn moves with time (a fade, a wash) so the render object keeps frames
/// coming only while it must.
///
/// ## Glyph and placeholder geometry
///
/// Leaf content bounds are a centred square of [kCatalogGlyphBoxFraction]
/// (**72%**) of `min(cellWidth, cellHeight)`, taken from the slot's own cell:
/// a section with larger cells draws larger content, and a baked sprite is
/// scaled to the box, so one baked size serves every section (see
/// [largestCatalogGlyphBox]). Placeholders use those bounds. The circle:
///
/// ```text
/// radius = glyphBounds.width * kCirclePlaceholderRadiusFactor  // 0.4
/// ```
///
/// MUST NOT size the circle against the full cell pitch: that oversizes it
/// relative to the glyph that replaces it.
///
/// ## What a leaf paints
///
/// The painter does not know how content is made; it reads the leaf's binding
/// at paint time and takes the first row that applies:
///
/// | The binding | Paint |
/// | ----------- | ----- |
/// | has a paintable with a **sprite** (a baked glyph on an atlas page) | queued; [endPass] draws every queued sprite of one page with one batched atlas draw. The pressed cell is queued scaled about its centre, so it needs no canvas transform and stays in its page's batch |
/// | none, or stage `none` | the placeholder of the leaf's style |
/// | stage `placeholder` of a glyph (a glyph not baked yet) | the circle |
/// | stage `placeholder` of other content | the binding's stand-in paintable (its thumbnail) |
/// | stage `firstFrame` or `full` | the binding's paintable, faded in over the placeholder when the content was not there at attach |
///
/// A paintable without a sprite paints itself. Where emoji are baked a glyph
/// is never in that row (unbaked is the circle, never text), so
/// [PanelCatalogDiagnostics.glyphParagraphDraws] counts only the glyphs a
/// strategy that draws text (the web) paints.
///
/// ## Placeholder styles
///
/// | [CatalogPlaceholderStyle] | Paint |
/// | ------------------------- | ----- |
/// | `circle` | filled circle |
/// | `thumbFirst` | rounded-rect silhouette |
/// | `shapedWash` | rounded rect swept by a moving band while [beginPass] allows it |
///
/// The wash is one gradient per pass in viewport coordinates, so every wash on
/// screen shimmers together and costs one shader however many there are.
///
/// ## Press highlight
///
/// When [paintLeaf] receives `pressProgress > 0`, a rounded rect on the **full
/// cell** is filled with the configured list-selector colour before scaled leaf
/// content. Highlight does not scale with glyph press.
///
/// ## Dispose
///
/// Call [dispose] when the owning render object disposes: it disposes and drops
/// the cached paragraphs, which hold engine memory outside the Dart heap.
final class CatalogLeafPainter {
  /// Creates a painter with an empty header paragraph cache.
  CatalogLeafPainter({required CatalogLeafPaintTheme theme}) : _theme = theme {
    _applyThemeColors(theme);
  }

  CatalogLeafPaintTheme _theme;

  // Fills reused by every leaf. A [Paint] is a heap object with a native-sized
  // backing buffer, so allocating one per leaf per frame is pure scroll-time
  // garbage. Colours only change with the theme; the highlight alpha and the
  // fade colour change per use and are written just before it, which is safe
  // because the canvas copies a paint's state at the draw call.
  final Paint _circlePaint = Paint();
  final Paint _thumbPaint = Paint();
  final Paint _washPaint = Paint();
  final Paint _fadePaint = Paint();
  final Paint _highlightPaint = Paint();

  final CatalogParagraphCache<_HeaderPaintKey> _headerParagraphs =
      CatalogParagraphCache(limit: kHeaderParagraphCacheLimit);
  final CatalogGlyphSpriteBatch _glyphSprites = CatalogGlyphSpriteBatch();

  // State of the open pass.
  Duration _frameTime = Duration.zero;
  Rect _viewport = Rect.zero;
  bool _animateWash = false;
  bool _needsFrame = false;
  ui.Shader? _washShader;

  /// Resolved paint tokens from [PanelCatalogThemeData] at the viewport.
  ///
  /// No-op when [value] equals the current snapshot (`==`). Clears the header
  /// paragraph cache when any section-header paint token changes.
  set theme(CatalogLeafPaintTheme value) {
    if (_theme == value) return;
    final headerPaintChanged =
        _theme.sectionHeaderStyle != value.sectionHeaderStyle ||
        _theme.sectionHeaderStartInset != value.sectionHeaderStartInset;
    _theme = value;
    _applyThemeColors(value);
    if (headerPaintChanged) {
      _headerParagraphs.clear();
    }
  }

  void _applyThemeColors(CatalogLeafPaintTheme theme) {
    _circlePaint.color = theme.circleColor;
    _thumbPaint.color = theme.thumbColor;
  }

  /// Releases cached paragraphs and buffers. Idempotent.
  void dispose() {
    _headerParagraphs.clear();
    _glyphSprites.dispose();
    _releaseWashShader();
  }

  /// Opens a paint pass at [frameTime] over [viewport] (canvas coordinates).
  ///
  /// [animateWash] is false when the host paused playback: washes then paint
  /// flat. The render object clears it together with the scope's pause layers.
  void beginPass({
    required Duration frameTime,
    required Rect viewport,
    required bool animateWash,
  }) {
    _frameTime = frameTime;
    _viewport = viewport;
    _animateWash = animateWash;
    _needsFrame = false;
  }

  /// Closes the pass: draws the glyph sprites queued by [paintLeaf], one
  /// batched atlas draw per page, with the same clip and transform as the
  /// pass. Returns whether something drawn moves with time, so another frame
  /// is needed.
  bool endPass(Canvas canvas) {
    _glyphSprites.flush(canvas);
    _releaseWashShader();
    return _needsFrame;
  }

  void _releaseWashShader() {
    _washShader?.dispose();
    _washShader = null;
  }

  /// Paints [header] at content [origin].
  ///
  /// Title paragraph is cached by title, typography, colour and layout width.
  /// Vertical placement centres the line in [CatalogHeaderSlot.height];
  /// horizontal placement adds [CatalogLeafPaintTheme.sectionHeaderStartInset]
  /// after the section's own left edge ([CatalogHeaderSlot.left]), and the
  /// text shares the section's [CatalogHeaderSlot.width].
  void paintHeader({
    required Canvas canvas,
    required Offset origin,
    required CatalogHeaderSlot header,
  }) {
    final theme = _theme;
    final headerStyle = theme.sectionHeaderStyle;
    final textWidth = math.max(
      0.0,
      header.width - theme.sectionHeaderStartInset,
    );
    final paragraph = _headerParagraphs.obtain(
      _HeaderPaintKey(
        title: header.title,
        style: headerStyle,
        width: textWidth,
      ),
      () {
        final builder =
            ui.ParagraphBuilder(
                headerStyle.getParagraphStyle(textScaler: TextScaler.noScaling),
              )
              ..pushStyle(headerStyle.getTextStyle())
              ..addText(header.title);
        return builder.build()
          ..layout(ui.ParagraphConstraints(width: textWidth));
      },
    );
    final textY = header.top + (header.height - paragraph.height) / 2;
    canvas.drawParagraph(
      paragraph,
      Offset(
        origin.dx + header.left + theme.sectionHeaderStartInset,
        origin.dy + textY,
      ),
    );
  }

  /// Paints one leaf cell, drawing what [bound] has reached (see the class
  /// table); a null [bound] is a leaf with no attach and paints its
  /// placeholder.
  ///
  /// [pressScale] is applied about the cell centre to leaf content using the
  /// viewport press factor (`0.8 + 0.2 * (1 - pressedProgress)`). `1` is
  /// identity: no save and scale.
  ///
  /// [pressProgress] drives the list-selector highlight on the **full cell
  /// rect** (unscaled). Skipped when the configured highlight colour is fully
  /// transparent or progress is `<= 0`.
  void paintLeaf({
    required Canvas canvas,
    required Offset origin,
    required CatalogLeafSlot slot,
    required CatalogBoundLeaf? bound,
    double pressScale = 1,
    double pressProgress = 0,
  }) {
    final theme = _theme;
    final cellRect = Rect.fromLTWH(
      origin.dx + slot.left,
      origin.dy + slot.top,
      slot.width,
      slot.height,
    );
    final glyphSize = slot.contentExtent;
    final glyphRect = Rect.fromCenter(
      center: cellRect.center,
      width: glyphSize,
      height: glyphSize,
    );

    if (pressProgress > 0 && theme.leafPressHighlightColor.a > 0) {
      final factor = pressProgress.clamp(0.0, 1.0);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          cellRect,
          Radius.circular(theme.leafPressSelectorRadius),
        ),
        _highlightPaint
          ..color = theme.leafPressHighlightColor.withValues(
            alpha: theme.leafPressHighlightColor.a * factor,
          ),
      );
    }

    // Read once: for a baked glyph this asks the atlas, which queues the reload
    // of a released page, so it is neither free nor to be repeated per leaf.
    final binding = bound?.binding;
    final sprite = binding?.paintable.sprite;
    if (sprite != null) {
      // A queued sprite carries the press scale in its own transform, so it
      // needs no canvas save and restore and stays in its page's batch.
      final center = cellRect.center;
      _glyphSprites.add(
        sprite,
        left: center.dx + (glyphRect.left - center.dx) * pressScale,
        top: center.dy + (glyphRect.top - center.dy) * pressScale,
        scale: glyphRect.width / sprite.source.width * pressScale,
      );
      return;
    }

    final scaled = pressScale != 1;
    if (scaled) {
      canvas
        ..save()
        ..translate(cellRect.center.dx, cellRect.center.dy)
        ..scale(pressScale)
        ..translate(-cellRect.center.dx, -cellRect.center.dy);
    }

    final style = slot.placeholderStyle;
    switch (binding?.readiness.stage) {
      case null || AssetStage.none:
        _paintStandIn(canvas, style, glyphRect);
      case AssetStage.placeholder:
        if (style == CatalogPlaceholderStyle.circle) {
          _paintStandIn(canvas, style, glyphRect);
        } else {
          binding!.paint(canvas, glyphRect);
        }
      case AssetStage.firstFrame || AssetStage.full:
        final opacity = bound!.opacityAt(_frameTime);
        if (opacity < 1) {
          _needsFrame = true;
          _paintStandIn(canvas, style, glyphRect, alpha: 1 - opacity);
        }
        if (slot.leaf.key is ContentKey$Unicode) {
          PanelCatalogDiagnostics.glyphParagraphDraws++;
        }
        binding!.paint(canvas, glyphRect, opacity: opacity);
    }

    if (scaled) {
      canvas.restore();
    }
  }

  /// The placeholder of [style] in [glyphRect], at [alpha] of its colour.
  void _paintStandIn(
    Canvas canvas,
    CatalogPlaceholderStyle style,
    Rect glyphRect, {
    double alpha = 1,
  }) {
    final theme = _theme;
    switch (style) {
      case CatalogPlaceholderStyle.circle:
        canvas.drawCircle(
          glyphRect.center,
          glyphRect.width * kCirclePlaceholderRadiusFactor,
          alpha == 1 ? _circlePaint : _faded(theme.circleColor, alpha),
        );
      case CatalogPlaceholderStyle.thumbFirst:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            glyphRect,
            Radius.circular(theme.placeholderCornerRadius),
          ),
          alpha == 1 ? _thumbPaint : _faded(theme.thumbColor, alpha),
        );
      case CatalogPlaceholderStyle.shapedWash:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            glyphRect,
            Radius.circular(theme.placeholderCornerRadius),
          ),
          alpha == 1 ? _wash() : _faded(theme.washColor, alpha),
        );
    }
  }

  Paint _faded(Color color, double alpha) =>
      _fadePaint..color = color.withValues(alpha: color.a * alpha);

  /// The wash paint: flat, or the pass's shared sweeping gradient.
  Paint _wash() {
    if (!_animateWash) {
      return _washPaint
        ..color = _theme.washColor
        ..shader = null;
    }
    _needsFrame = true;
    // The paint's own alpha multiplies a shader's, so the colours live in the
    // gradient and the paint is opaque.
    return _washPaint
      ..color = const Color(0xFF000000)
      ..shader = _washShader ??= _createWashShader();
  }

  // One band, half a viewport wide, travels from before the left edge to
  // beyond the right edge once per [CatalogLeafPaintTheme.washPeriod]. The
  // phase comes from the frame's timestamp, so washes in every viewport of the
  // app are in step.
  ui.Shader _createWashShader() {
    final theme = _theme;
    final period = theme.washPeriod.inMicroseconds;
    final phase = period <= 0
        ? 0.0
        : (_frameTime.inMicroseconds % period) / period;
    final band = math.max(1.0, _viewport.width * 0.5);
    final start = _viewport.left - band + phase * (_viewport.width + band);
    return ui.Gradient.linear(
      Offset(start, 0),
      Offset(start + band, 0),
      [theme.washColor, theme.washHighlightColor, theme.washColor],
      const [0, 0.5, 1],
    );
  }
}

/// Cache key for header paragraphs (title, style, layout width).
final class _HeaderPaintKey {
  const _HeaderPaintKey({
    required this.title,
    required this.style,
    required this.width,
  });

  final String title;
  final TextStyle style;
  final double width;

  @override
  bool operator ==(Object other) =>
      other is _HeaderPaintKey &&
      other.title == title &&
      other.style == style &&
      other.width == width;

  @override
  int get hashCode => Object.hash(title, style, width);
}
