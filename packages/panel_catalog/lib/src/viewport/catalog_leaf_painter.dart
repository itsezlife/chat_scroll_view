import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:catalog_assets/glyph_atlas.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/painting.dart';
import 'package:panel_catalog/panel_catalog_diagnostics.dart';
import 'package:panel_catalog/src/model/catalog_glyph_box.dart';
import 'package:panel_catalog/src/viewport/catalog_cell_paint.dart';
import 'package:panel_catalog/src/viewport/catalog_glyph_sprite_batch.dart';
import 'package:panel_catalog/src/viewport/catalog_leaf_paint_theme.dart';
import 'package:panel_catalog/src/viewport/catalog_paragraph_cache.dart';
import 'package:panel_catalog/src/viewport/catalog_slot_projection.dart';

/// Most section-header paragraphs one painter keeps; a header is keyed by title,
/// style and layout width, so a resize adds one per visible header per step.
/// Far above the headers of one screen (a handful).
const int kHeaderParagraphCacheLimit = 64;

/// Most glyph paragraphs one painter keeps on the paragraph path (the web).
///
/// A paragraph is keyed by glyph and layout width, so a window that is resized
/// step by step makes every visible glyph a new key per step. The least
/// recently drawn paragraph is dropped past this count. It is far above what
/// one screen draws, so scrolling and a settled layout never evict.
const int kGlyphParagraphCacheLimit = 1024;

/// Paints catalog headers and leaves onto a [Canvas].
///
/// Owns bounded paragraph caches for section titles and unicode glyphs so
/// repeated paint of the same visible band does not rebuild text layouts every
/// frame.
/// Does **not** own layout slots, scroll offset, or asset readiness — the
/// render object passes content [origin], slot geometry,
/// [CatalogCellPaint], and [CatalogLeafPaintTheme].
///
/// ## Coordinate contract
///
/// [origin] is the paint origin of content-y `0` after scroll translation
/// (`paintOffset.translate(0, −scrollOffset)`). A slot at content-y `top`
/// is drawn at `origin.dy + top`. Callers MUST clip to the viewport before
/// invoking paint methods if overdraw outside the viewport is unwanted.
///
/// ## Glyph and placeholder geometry
///
/// Leaf glyph draw bounds are a centered square of
/// [kCatalogGlyphBoxFraction] (**72%**) of `min(cellWidth, cellHeight)`, taken
/// from the slot's own cell: a section with larger cells draws a larger glyph,
/// and a baked sprite is scaled to the box, so one baked size serves every
/// section (see [largestCatalogGlyphBox]). Circle placeholders use those
/// bounds:
///
/// ```text
/// radius = glyphBounds.width * kCirclePlaceholderRadiusFactor  // 0.4
/// ```
///
/// MUST NOT size the circle against the full cell pitch — that oversizes
/// relative to the eventual glyph.
///
/// ## Unicode glyphs
///
/// A glyph whose asset has a **sprite** (a baked glyph on an atlas page) is not
/// drawn by [paintLeaf] at all: it is queued, and [flushGlyphSprites] draws
/// every queued sprite of one page with one batched atlas draw. The pressed
/// cell is queued scaled about its center, so it needs no canvas transform and
/// stays in its page's batch.
///
/// A glyph without a sprite paints itself from a cached [ui.Paragraph] keyed by
/// `(glyph, logicalWidth)` (the web strategy, or a surface whose cache bakes
/// nothing). Layout runs **once** when the paragraph is created. Scroll paints
/// only [Canvas.drawParagraph] for that cached instance. Where emoji are baked
/// this path is never reached for unicode: an unbaked glyph is presented as the
/// circle placeholder, not as text, and no paragraph is built for it.
///
/// The glyph cache holds at most [kGlyphParagraphCacheLimit] paragraphs, least
/// recently drawn out first: the width is part of the key, so
/// a window resized step by step would otherwise add a screenful per step for
/// good. The section-header cache is bounded the same way by
/// [kHeaderParagraphCacheLimit].
///
/// ## Paint switch
///
/// | [CatalogCellPaint] | Paint |
/// |--------------------|--------|
/// | [CatalogCellPaint.circle] | Filled circle |
/// | [CatalogCellPaint.thumb] / [CatalogCellPaint.wash] / [CatalogCellPaint.failed] | Rounded rect stand-in |
/// | [CatalogCellPaint.content] + unicode with a sprite | Queued sprite (batched per page) |
/// | [CatalogCellPaint.content] + unicode without | Cached glyph paragraph |
/// | [CatalogCellPaint.content] + document | Ready-path stand-in rect until media decode lands |
///
/// ## Press highlight
///
/// When [paintLeaf] receives [pressProgress] > 0, a rounded rect on the **full
/// cell** is filled with the configured list-selector color before scaled leaf
/// content. Highlight does not scale with glyph press.
///
/// ## Theme vs layout constants
///
/// [CatalogLeafPaintTheme] supplies section header typography and insets plus
/// stand-in / press colors and radii. Glyph bounds use fixed fractions
/// ([kCatalogGlyphBoxFraction], `0.85` for the paragraph's font size,
/// [kCirclePlaceholderRadiusFactor]) — not theme fields.
///
/// ## Dispose
///
/// Call [dispose] when the owning render object disposes: it disposes and
/// drops the cached paragraphs, which hold engine memory outside the Dart heap
/// (the caches dispose the ones they evict as well).
final class CatalogLeafPainter {
  /// Creates a painter with empty paragraph caches.
  CatalogLeafPainter({required CatalogLeafPaintTheme theme}) : _theme = theme {
    _placeholderPaint.color = theme.placeholderColor;
    _documentStandInPaint.color = theme.documentStandInColor;
  }

  CatalogLeafPaintTheme _theme;

  /// Fills reused by every leaf. A [Paint] is a heap object with a native-sized
  /// backing buffer, so allocating one per leaf per frame is pure scroll-time
  /// garbage. Colors only change with the theme (see [theme]); the highlight
  /// alpha changes per press frame and is written just before use, which is
  /// safe because the canvas copies a paint's state at the draw call.
  final Paint _placeholderPaint = Paint();
  final Paint _documentStandInPaint = Paint();
  final Paint _highlightPaint = Paint();

  final CatalogParagraphCache<_HeaderPaintKey> _headerParagraphs =
      CatalogParagraphCache(limit: kHeaderParagraphCacheLimit);
  final CatalogParagraphCache<_GlyphPaintKey> _glyphParagraphs =
      CatalogParagraphCache(limit: kGlyphParagraphCacheLimit);
  final CatalogGlyphSpriteBatch _glyphSprites = CatalogGlyphSpriteBatch();

  /// Resolved paint tokens from [PanelCatalogThemeData] at the viewport.
  ///
  /// No-op when [value] equals the current snapshot (`==`). Clears header
  /// paragraph cache when any section-header paint token changes.
  set theme(CatalogLeafPaintTheme value) {
    if (_theme == value) return;
    final headerPaintChanged =
        _theme.sectionHeaderStyle != value.sectionHeaderStyle ||
        _theme.sectionHeaderStartInset != value.sectionHeaderStartInset;
    _theme = value;
    _placeholderPaint.color = value.placeholderColor;
    _documentStandInPaint.color = value.documentStandInColor;
    if (headerPaintChanged) {
      _headerParagraphs.clear();
    }
  }

  /// Releases cached paragraphs. Idempotent.
  void dispose() {
    _headerParagraphs.clear();
    _glyphParagraphs.clear();
    _glyphSprites.dispose();
  }

  /// Draws the glyph sprites queued by [paintLeaf] since the last flush, one
  /// batched atlas draw per page. Call once at the end of each paint pass, with
  /// the same clip and transform as the pass.
  void flushGlyphSprites(Canvas canvas) => _glyphSprites.flush(canvas);

  /// Paints [header] at content [origin].
  ///
  /// Title paragraph is cached by title, typography, color, and layout width.
  /// Vertical placement centers the line in [CatalogHeaderSlot.height];
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

  /// Paints one leaf cell for [presentation].
  ///
  /// Glyph draw bounds are ~72% of the cell's shorter side, centered. Circle
  /// placeholders use those bounds, not the full cell rect. Document
  /// [CatalogCellPaint.content] may still paint a stand-in while media
  /// decode is stubbed — identity and readiness are already resolved; bytes
  /// are not this painter’s concern.
  ///
  /// [pressScale] is applied about the cell center to leaf content using the
  /// viewport press factor (`0.8 + 0.2 * (1 − pressedProgress)`). `1` is
  /// identity — no save/scale.
  ///
  /// [pressProgress] drives the list-selector highlight on the **full cell
  /// rect** (unscaled). Skipped when the configured highlight color is fully
  /// transparent or progress is `≤ 0`.
  ///
  /// [sprite] is the leaf's baked glyph when its asset has one. A unicode leaf
  /// presented as content with a sprite is queued for [flushGlyphSprites]
  /// instead of being drawn here.
  void paintLeaf({
    required Canvas canvas,
    required Offset origin,
    required CatalogLeafSlot slot,
    required CatalogCellPaint presentation,
    AtlasSprite? sprite,
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
    final glyphSize = catalogGlyphBoxExtent(slot.width, slot.height);
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

    // A queued sprite carries the press scale in its own transform, so it needs
    // no canvas save and restore and stays in its page's batch.
    final unicode = slot.leaf.key;
    final queuesSprite =
        presentation == CatalogCellPaint.content &&
        unicode is ContentKey$Unicode &&
        sprite != null;
    if (queuesSprite) {
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
      canvas.save();
      canvas.translate(cellRect.center.dx, cellRect.center.dy);
      canvas.scale(pressScale);
      canvas.translate(-cellRect.center.dx, -cellRect.center.dy);
    }

    switch (presentation) {
      case CatalogCellPaint.circle:
        canvas.drawCircle(
          glyphRect.center,
          glyphRect.width * kCirclePlaceholderRadiusFactor,
          _placeholderPaint,
        );
      case CatalogCellPaint.thumb:
      case CatalogCellPaint.wash:
      case CatalogCellPaint.failed:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            glyphRect,
            Radius.circular(theme.standInCornerRadius),
          ),
          _placeholderPaint,
        );
      case CatalogCellPaint.content:
        switch (unicode) {
          case ContentKey$Unicode(:final sequence):
            _paintGlyph(canvas, glyphRect, sequence);
          case ContentKey$Document() || ContentKey$External():
            canvas.drawRRect(
              RRect.fromRectAndRadius(
                glyphRect,
                Radius.circular(theme.standInCornerRadius),
              ),
              _documentStandInPaint,
            );
        }
    }

    if (scaled) {
      canvas.restore();
    }
  }

  void _paintGlyph(Canvas canvas, Rect glyphRect, String glyph) {
    PanelCatalogDiagnostics.glyphParagraphDraws++;
    final paragraph = _paragraphForGlyph(glyph, glyphRect.width);
    canvas.drawParagraph(
      paragraph,
      Offset(
        glyphRect.left,
        glyphRect.top + (glyphRect.height - paragraph.height) / 2,
      ),
    );
  }

  /// Cache lookup / create for one glyph paragraph at [logicalWidth].
  ui.Paragraph _paragraphForGlyph(String glyph, double logicalWidth) {
    final key = _GlyphPaintKey(glyph, logicalWidth);
    return _glyphParagraphs.obtain(key, () {
      final builder = ui.ParagraphBuilder(
        ui.ParagraphStyle(
          textAlign: TextAlign.center,
          fontSize: logicalWidth * 0.85,
        ),
      )..addText(glyph);
      return builder.build()
        ..layout(ui.ParagraphConstraints(width: logicalWidth));
    });
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

/// Cache key for glyph paragraphs (glyph + layout width).
///
/// Width is part of the key so a span/pitch change that alters glyph bounds
/// does not reuse a paragraph laid out for a different font size.
final class _GlyphPaintKey {
  const _GlyphPaintKey(this.glyph, this.width);

  final String glyph;
  final double width;

  @override
  bool operator ==(Object other) =>
      other is _GlyphPaintKey && other.glyph == glyph && other.width == width;

  @override
  int get hashCode => Object.hash(glyph, width);
}
