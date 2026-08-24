import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:panel_catalog/src/model/catalog_leaf.dart';
import 'package:panel_catalog/src/model/catalog_leaf_presentation.dart';
import 'package:panel_catalog/src/viewport/catalog_slot_projection.dart';

/// Paints catalog headers and leaves onto a [Canvas].
///
/// Owns paragraph caches for section titles and unicode glyphs so repeated
/// paint of the same visible band does not rebuild text layouts every frame.
/// Does **not** own layout slots, scroll offset, or asset readiness — the
/// render object passes content [origin], slot geometry, and
/// [CatalogLeafPresentation].
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
/// ## Dispose
///
/// Call [dispose] when the owning render object disposes to drop cached
/// paragraphs. Clearing maps is enough — [ui.Paragraph] does not require a
/// native dispose in current Flutter.
final class CatalogLeafPainter {
  /// Creates a painter with empty paragraph caches.
  CatalogLeafPainter({
    required Color placeholderColor,
    required Color leafPressHighlightColor,
    required Color sectionHeaderColor,
    required Color documentStandInColor,
    required double leafPressSelectorRadius,
    required double standInCornerRadius,
  }) : _placeholderColor = placeholderColor,
       _leafPressHighlightColor = leafPressHighlightColor,
       _sectionHeaderColor = sectionHeaderColor,
       _documentStandInColor = documentStandInColor,
       _leafPressSelectorRadius = leafPressSelectorRadius,
       _standInCornerRadius = standInCornerRadius;

  Color _placeholderColor;
  Color _leafPressHighlightColor;
  Color _sectionHeaderColor;
  Color _documentStandInColor;
  double _leafPressSelectorRadius;
  double _standInCornerRadius;
  final Map<_HeaderPaintKey, ui.Paragraph> _headerParagraphs = {};
  final Map<_GlyphPaintKey, ui.Paragraph> _glyphParagraphs = {};

  /// Updates the circle / stand-in fill color.
  set placeholderColor(Color value) => _placeholderColor = value;

  /// List-selector wash on pressed cells. Fully transparent disables highlight.
  set leafPressHighlightColor(Color value) => _leafPressHighlightColor = value;

  /// Section header title color. Clears header paragraph cache on change.
  set sectionHeaderColor(Color value) {
    if (_sectionHeaderColor == value) return;
    _sectionHeaderColor = value;
    _headerParagraphs.clear();
  }

  /// Document ready-path stand-in fill.
  set documentStandInColor(Color value) => _documentStandInColor = value;

  /// Corner radius for rounded-rect stand-ins (logical px).
  set standInCornerRadius(double value) => _standInCornerRadius = value;

  /// Corner radius for press highlight on the full cell rect.
  set leafPressSelectorRadius(double value) => _leafPressSelectorRadius = value;

  /// Releases cached paragraphs. Idempotent.
  void dispose() {
    _headerParagraphs.clear();
    _glyphParagraphs.clear();
  }

  /// Paints [header] at content [origin].
  ///
  /// Title paragraph is cached by [CatalogHeaderSlot.title]. Layout width is
  /// `contentWidth − padding.horizontal`. Vertical placement adds a small
  /// inset (`+ 8`) below [CatalogHeaderSlot.top] so the label sits inside the
  /// header band rather than flush to its top edge.
  void paintHeader({
    required Canvas canvas,
    required Offset origin,
    required CatalogHeaderSlot header,
    required double contentWidth,
    required EdgeInsets padding,
  }) {
    final paragraph = _headerParagraphs.putIfAbsent(
      _HeaderPaintKey(header.title, _sectionHeaderColor),
      () {
      final builder =
          ui.ParagraphBuilder(
              ui.ParagraphStyle(fontSize: 13, fontWeight: FontWeight.w600),
            )
            ..pushStyle(ui.TextStyle(color: _sectionHeaderColor))
            ..addText(header.title);
      return builder.build()..layout(
        ui.ParagraphConstraints(width: contentWidth - padding.horizontal),
      );
    },
    );
    canvas.drawParagraph(
      paragraph,
      Offset(origin.dx + padding.left, origin.dy + header.top + 8),
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

    if (pressProgress > 0 && _leafPressHighlightColor.a > 0) {
      final factor = pressProgress.clamp(0.0, 1.0);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          cellRect,
          Radius.circular(_leafPressSelectorRadius),
        ),
        Paint()
          ..color = _leafPressHighlightColor.withValues(
            alpha: _leafPressHighlightColor.a * factor,
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
          Paint()..color = _placeholderColor,
        );
      case CatalogLeafPresentation.thumbFirstPlaceholder:
      case CatalogLeafPresentation.shapedLoadingWash:
      case CatalogLeafPresentation.failed:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            glyphRect,
            Radius.circular(_standInCornerRadius),
          ),
          Paint()..color = _placeholderColor,
        );
      case CatalogLeafPresentation.content:
        switch (slot.leaf) {
          case UnicodeCatalogLeaf(:final glyph):
            _paintGlyph(canvas, glyphRect, glyph);
          case DocumentCatalogLeaf():
            canvas.drawRRect(
              RRect.fromRectAndRadius(
                glyphRect,
                Radius.circular(_standInCornerRadius),
              ),
              Paint()..color = _documentStandInColor,
            );
        }
    }

    if (scaled) {
      canvas.restore();
    }
  }

  void _paintGlyph(Canvas canvas, Rect glyphRect, String glyph) {
    final key = _GlyphPaintKey(glyph, glyphRect.width);
    final paragraph = _glyphParagraphs.putIfAbsent(key, () {
      final builder = ui.ParagraphBuilder(
        ui.ParagraphStyle(
          textAlign: TextAlign.center,
          fontSize: glyphRect.width * 0.85,
        ),
      )..addText(glyph);
      return builder.build();
    });
    paragraph.layout(ui.ParagraphConstraints(width: glyphRect.width));
    canvas.drawParagraph(
      paragraph,
      Offset(
        glyphRect.left,
        glyphRect.top + (glyphRect.height - paragraph.height) / 2,
      ),
    );
  }
}

/// Cache key for header paragraphs (title + title color).
final class _HeaderPaintKey {
  const _HeaderPaintKey(this.title, this.color);

  final String title;
  final Color color;

  @override
  bool operator ==(Object other) =>
      other is _HeaderPaintKey &&
      other.title == title &&
      other.color == color;

  @override
  int get hashCode => Object.hash(title, color);
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
