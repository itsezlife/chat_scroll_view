import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:panel_catalog/src/model/catalog_leaf.dart';
import 'package:panel_catalog/src/model/catalog_leaf_presentation.dart';
import 'package:panel_catalog/src/viewport/catalog_leaf_paint_theme.dart';
import 'package:panel_catalog/src/viewport/catalog_slot_projection.dart';

/// Paints catalog headers and leaves onto a [Canvas].
///
/// Owns paragraph caches for section titles and unicode glyphs so repeated
/// paint of the same visible band does not rebuild text layouts every frame.
/// Does **not** own layout slots, scroll offset, or asset readiness — the
/// render object passes content [origin], slot geometry,
/// [CatalogLeafPresentation], and [CatalogLeafPaintTheme].
///
/// ## Cold-start warm-up
///
/// [ensureGlyphParagraph] builds and layouts a glyph paragraph without
/// painting. [rasterizeGlyphsForWarmup] draws those paragraphs into a
/// temporary picture, awaits [ui.Picture.toImage], then disposes the image so
/// the rasterizer’s color-emoji path is exercised before the first user
/// fling. Callers MUST invoke warm-up from open / idle — not from scroll
/// ticks (offscreen `toImage` on the fling path regresses frame time).
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
/// Leaf glyph draw bounds are a centered square ≈ **72%** of
/// `min(cellWidth, cellHeight)`. Circle placeholders use those bounds:
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
/// Glyphs use a cached [ui.Paragraph] keyed by `(glyph, logicalWidth)`.
/// Layout runs **once** when the paragraph is created. Scroll paints only
/// [Canvas.drawParagraph] for that cached instance.
///
/// ## Presentation switch
///
/// | [CatalogLeafPresentation] | Paint |
/// |---------------------------|--------|
/// | [CatalogLeafPresentation.circlePlaceholder] | Filled circle |
/// | [CatalogLeafPresentation.thumbFirstPlaceholder] / [CatalogLeafPresentation.shapedLoadingWash] / [CatalogLeafPresentation.failed] | Rounded rect stand-in |
/// | [CatalogLeafPresentation.content] + unicode | Cached glyph paragraph |
/// | [CatalogLeafPresentation.content] + document | Ready-path stand-in rect until media decode lands |
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
/// stand-in / press colors and radii. Glyph bounds use fixed fractions (`0.72`,
/// `0.85`, [kCirclePlaceholderRadiusFactor]) — not theme fields.
///
/// ## Dispose
///
/// Call [dispose] when the owning render object disposes to drop cached
/// paragraphs. Clearing maps is enough — [ui.Paragraph] does not require a
/// native dispose in current Flutter.
final class CatalogLeafPainter {
  /// Creates a painter with empty paragraph caches.
  CatalogLeafPainter({required CatalogLeafPaintTheme theme}) : _theme = theme;

  CatalogLeafPaintTheme _theme;
  final Map<_HeaderPaintKey, ui.Paragraph> _headerParagraphs = {};
  final Map<_GlyphPaintKey, ui.Paragraph> _glyphParagraphs = {};

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
    if (headerPaintChanged) {
      _headerParagraphs.clear();
    }
  }

  /// Releases cached paragraphs. Idempotent.
  void dispose() {
    _headerParagraphs.clear();
    _glyphParagraphs.clear();
  }

  /// Paints [header] at content [origin].
  ///
  /// Title paragraph is cached by title, typography, color, and layout width.
  /// Vertical placement centers the line in [CatalogHeaderSlot.height];
  /// horizontal placement adds [CatalogLeafPaintTheme.sectionHeaderStartInset]
  /// after [padding.left].
  void paintHeader({
    required Canvas canvas,
    required Offset origin,
    required CatalogHeaderSlot header,
    required double contentWidth,
    required EdgeInsets padding,
  }) {
    final theme = _theme;
    final headerStyle = theme.sectionHeaderStyle;
    final textWidth = math.max(
      0.0,
      contentWidth - padding.horizontal - theme.sectionHeaderStartInset,
    );
    final paragraph = _headerParagraphs.putIfAbsent(
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
        origin.dx + padding.left + theme.sectionHeaderStartInset,
        origin.dy + textY,
      ),
    );
  }

  /// Paints one leaf cell for [presentation].
  ///
  /// Glyph draw bounds are ~72% of the cell pitch, centered. Circle
  /// placeholders use those bounds, not the full cell rect. Document
  /// [CatalogLeafPresentation.content] may still paint a stand-in while media
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
  void paintLeaf({
    required Canvas canvas,
    required Offset origin,
    required CatalogLeafSlot slot,
    required CatalogLeafPresentation presentation,
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
    final glyphSize = math.min(slot.width, slot.height) * 0.72;
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
        Paint()
          ..color = theme.leafPressHighlightColor.withValues(
            alpha: theme.leafPressHighlightColor.a * factor,
          ),
      );
    }

    final scaled = pressScale != 1;
    if (scaled) {
      canvas.save();
      canvas.translate(cellRect.center.dx, cellRect.center.dy);
      canvas.scale(pressScale);
      canvas.translate(-cellRect.center.dx, -cellRect.center.dy);
    }

    switch (presentation) {
      case CatalogLeafPresentation.circlePlaceholder:
        canvas.drawCircle(
          glyphRect.center,
          glyphRect.width * kCirclePlaceholderRadiusFactor,
          Paint()..color = theme.placeholderColor,
        );
      case CatalogLeafPresentation.thumbFirstPlaceholder:
      case CatalogLeafPresentation.shapedLoadingWash:
      case CatalogLeafPresentation.failed:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            glyphRect,
            Radius.circular(theme.standInCornerRadius),
          ),
          Paint()..color = theme.placeholderColor,
        );
      case CatalogLeafPresentation.content:
        switch (slot.leaf) {
          case UnicodeCatalogLeaf(:final glyph):
            _paintGlyph(canvas, glyphRect, glyph);
          case DocumentCatalogLeaf():
            canvas.drawRRect(
              RRect.fromRectAndRadius(
                glyphRect,
                Radius.circular(theme.standInCornerRadius),
              ),
              Paint()..color = theme.documentStandInColor,
            );
        }
    }

    if (scaled) {
      canvas.restore();
    }
  }

  void _paintGlyph(Canvas canvas, Rect glyphRect, String glyph) {
    final paragraph = _paragraphForGlyph(glyph, glyphRect.width);
    canvas.drawParagraph(
      paragraph,
      Offset(
        glyphRect.left,
        glyphRect.top + (glyphRect.height - paragraph.height) / 2,
      ),
    );
  }

  /// Returns a laid-out [ui.Paragraph] for [glyph] at [logicalWidth].
  ///
  /// Creates and layouts on first use for that `(glyph, width)` key; later
  /// calls reuse the cache. Does **not** draw and does **not** notify the
  /// owner. [logicalWidth] ≤ 0 yields a paragraph laid out against that
  /// width (caller SHOULD skip). Used by [rasterizeGlyphsForWarmup] and by
  /// the owning render object’s cold-start band walk.
  ui.Paragraph ensureGlyphParagraph(String glyph, double logicalWidth) =>
      _paragraphForGlyph(glyph, logicalWidth);

  /// Cache lookup / create for one glyph paragraph at [logicalWidth].
  ui.Paragraph _paragraphForGlyph(String glyph, double logicalWidth) {
    final key = _GlyphPaintKey(glyph, logicalWidth);
    return _glyphParagraphs.putIfAbsent(key, () {
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

  /// Offscreen-rasterizes unique [glyphs] at [logicalWidth] (device pixels).
  ///
  /// For each chunk: builds a temporary picture of laid-out paragraphs,
  /// awaits [ui.Picture.toImage], disposes the image and picture. Side
  /// effect is exercising the rasterizer’s color-emoji path so a later
  /// on-screen [paintLeaf] is cheaper. Empty [glyphs] or [logicalWidth] ≤ 0
  /// is a silent no-op. Failed chunks are skipped (MUST NOT throw to the
  /// host). Yields after each chunk so an in-flight open animation can
  /// schedule. MUST NOT be called from the scroll/paint tick path.
  Future<void> rasterizeGlyphsForWarmup({
    required Iterable<String> glyphs,
    required double logicalWidth,
    int chunkSize = 16,
  }) async {
    if (logicalWidth <= 0) return;
    final unique = <String>{};
    for (final g in glyphs) {
      if (g.isNotEmpty) unique.add(g);
    }
    if (unique.isEmpty) return;

    final views = ui.PlatformDispatcher.instance.views;
    final dpr = views.isEmpty ? 1.0 : views.first.devicePixelRatio;
    final pixelW = math.max(1, (logicalWidth * dpr).ceil());
    final list = unique.toList(growable: false);

    for (var i = 0; i < list.length; i += chunkSize) {
      final end = math.min(i + chunkSize, list.length);
      final chunk = list.sublist(i, end);
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.scale(dpr);
      var y = 0.0;
      for (final glyph in chunk) {
        final paragraph = _paragraphForGlyph(glyph, logicalWidth);
        final dy = (logicalWidth - paragraph.height) / 2;
        canvas.drawParagraph(paragraph, Offset(0, y + dy));
        y += logicalWidth;
      }
      final picture = recorder.endRecording();
      final pixelH = math.max(1, (y * dpr).ceil());
      try {
        final image = await picture.toImage(pixelW, pixelH);
        image.dispose();
      } on Object {
        // Warm-up must never break open; skip failed chunks.
      } finally {
        picture.dispose();
      }
      // Let the open animation / input schedule run between chunks.
      await Future<void>.delayed(Duration.zero);
    }
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
