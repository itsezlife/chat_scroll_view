import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/painting.dart';
import 'package:meta/meta.dart';
import 'package:panel_catalog/panel_catalog_diagnostics.dart';
import 'package:panel_catalog/src/model/catalog_glyph_box.dart'
    show kCirclePlaceholderRadiusFactor;
import 'package:panel_catalog/src/model/catalog_leaf.dart';
import 'package:panel_catalog/src/model/catalog_section_action.dart';
import 'package:panel_catalog/src/viewport/catalog_glyph_sprite_batch.dart';
import 'package:panel_catalog/src/viewport/catalog_leaf_binding_pool.dart';
import 'package:panel_catalog/src/viewport/catalog_leaf_paint_theme.dart';
import 'package:panel_catalog/src/viewport/catalog_paragraph_cache.dart';
import 'package:panel_catalog/src/viewport/catalog_slot_projection.dart';

/// Most text paragraphs one painter keeps; a paragraph is keyed by text, style
/// and layout width, so a resize adds a few per visible header per step (title,
/// action label, action icon). Far above the headers of one screen (a
/// handful).
const int kHeaderParagraphCacheLimit = 64;

/// Space between an action's label and its icon.
const double _kActionPartGap = 4;

/// An action icon is drawn this much larger than the header text.
const double _kActionIconScale = 1.3;

/// Paints catalog headers and leaves onto a [Canvas].
///
/// Owns a bounded paragraph cache for section titles, action labels and empty
/// messages so repeated paint of the same visible band does not rebuild text
/// layouts every frame. Does **not**
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
    _applyTheme(theme);
  }

  CatalogLeafPaintTheme _theme;

  // The header style at regular weight, derived once per theme rather than per
  // paint.
  late TextStyle _messageStyle;

  // Fills reused by every leaf. A [Paint] is a heap object with a native-sized
  // backing buffer, so allocating one per leaf per frame is pure scroll-time
  // garbage. Colours only change with the theme; the highlight alpha and the
  // fade colour change per use and are written just before it, which is safe
  // because the canvas copies a paint's state at the draw call.
  final Paint _circlePaint = Paint();
  final Paint _thumbPaint = Paint();
  final Paint _skeletonPaint = Paint();
  final Paint _washPaint = Paint();
  final Paint _fadePaint = Paint();
  final Paint _highlightPaint = Paint();

  final CatalogParagraphCache<_TextPaintKey> _textParagraphs =
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
    _applyTheme(value);
    if (headerPaintChanged) {
      _textParagraphs.clear();
    }
  }

  void _applyTheme(CatalogLeafPaintTheme theme) {
    _circlePaint.color = theme.circleColor;
    _thumbPaint.color = theme.thumbColor;
    _skeletonPaint.color = theme.skeletonColor;
    _messageStyle = theme.sectionHeaderStyle.copyWith(
      fontWeight: FontWeight.w400,
    );
  }

  /// Releases cached paragraphs and buffers. Idempotent.
  void dispose() {
    _textParagraphs.clear();
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

  /// Paints [header] at content [origin]: the title, and the trailing action
  /// when the section has one.
  ///
  /// Paragraphs come from the bounded cache, keyed by text, typography, layout
  /// width and direction. Vertical placement centres each line in
  /// [CatalogHeaderSlot.height]. The title starts
  /// [CatalogLeafPaintTheme.sectionHeaderStartInset] in from the band's start
  /// edge (left in a left-to-right header, right in a right-to-left one) and
  /// ends where the action's hit area begins, or at the band's end edge when
  /// there is no action; the action sits at the end edge.
  void paintHeader({
    required Canvas canvas,
    required Offset origin,
    required CatalogHeaderSlot header,
  }) {
    final theme = _theme;
    final inset = theme.sectionHeaderStartInset;
    final direction = header.textDirection;
    final ltr = direction == TextDirection.ltr;
    final action = _actionLayout(header);
    final bandEnd = header.left + header.width;
    // The title's box, from its end-side limit to its start-side limit.
    final titleLeft = ltr
        ? header.left + inset
        : action?.hit.right ?? header.left;
    final titleRight = ltr ? action?.hit.left ?? bandEnd : bandEnd - inset;
    final paragraph = _paragraph(
      header.title,
      theme.sectionHeaderStyle,
      width: math.max<double>(0, titleRight - titleLeft),
      direction: direction,
    );
    final textY = header.top + (header.height - paragraph.height) / 2;
    canvas.drawParagraph(
      paragraph,
      Offset(origin.dx + titleLeft, origin.dy + textY),
    );
    if (action == null) return;
    // Parts read start to end: the label first, then the icon. A right-to-left
    // header puts the label at the right, so its parts are laid out from the
    // left edge in the opposite order.
    var x = ltr
        ? action.hit.right - inset - action.width
        : action.hit.left + inset;
    // A painted icon has a box of its own, at the action's end edge.
    if (header.action?.painter case final paint?) {
      final box = Rect.fromLTWH(
        origin.dx +
            (ltr
                ? action.hit.right - inset - kCatalogActionIconExtent
                : action.hit.left + inset),
        origin.dy + header.top + (header.height - kCatalogActionIconExtent) / 2,
        kCatalogActionIconExtent,
        kCatalogActionIconExtent,
      );
      paint(
        canvas,
        box,
        theme.sectionHeaderStyle.color ?? const Color(0xFF000000),
      );
      // The parts start left of the whole action left to right; right to
      // left they start at the box, which comes first there.
      if (!ltr) x += kCatalogActionIconExtent + _kActionPartGap;
    }
    final parts = [?action.label, ?action.icon];
    for (final part in ltr ? parts : parts.reversed) {
      canvas.drawParagraph(
        part,
        Offset(
          origin.dx + x,
          origin.dy + header.top + (header.height - part.height) / 2,
        ),
      );
      x += part.maxIntrinsicWidth + _kActionPartGap;
    }
  }

  /// The hit area of [header]'s trailing action in content coordinates, or null
  /// when the section has none.
  ///
  /// The whole band tall, from the action's own start (less the header start
  /// inset) to the band's end edge (the right edge, or the left edge in a
  /// right-to-left header), and at least [kCatalogActionMinHitWidth] wide.
  Rect? sectionActionBounds(CatalogHeaderSlot header) =>
      _actionLayout(header)?.hit;

  ({Rect hit, ui.Paragraph? label, ui.Paragraph? icon, double width})?
  _actionLayout(CatalogHeaderSlot header) {
    final action = header.action;
    if (action == null) return null;
    final style = _theme.sectionHeaderStyle;
    final direction = header.textDirection;
    final label = action.label;
    final icon = action.icon;
    // Left-aligned in a band-wide box: a part is drawn at its own x whatever
    // the direction; the direction only orders its bidirectional text.
    final labelParagraph = switch (label) {
      final label? => _paragraph(
        label,
        style,
        width: header.width,
        direction: direction,
        align: TextAlign.left,
      ),
      null => null,
    };
    final iconParagraph = switch (icon) {
      final icon? => _paragraph(
        String.fromCharCode(icon.codePoint),
        style.copyWith(
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          fontSize: (style.fontSize ?? 14) * _kActionIconScale,
          fontWeight: FontWeight.w400,
        ),
        width: header.width,
        direction: direction,
        align: TextAlign.left,
      ),
      null => null,
    };
    final painted = action.painter == null ? 0.0 : kCatalogActionIconExtent;
    final width =
        (labelParagraph?.maxIntrinsicWidth ?? 0) +
        (iconParagraph?.maxIntrinsicWidth ?? 0) +
        painted +
        switch ((labelParagraph, iconParagraph ?? (painted > 0 ? 0 : null))) {
          (_?, _?) => _kActionPartGap,
          _ => 0,
        };
    final hitWidth = math.min(
      header.width,
      math.max(
        kCatalogActionMinHitWidth,
        width + 2 * _theme.sectionHeaderStartInset,
      ),
    );
    final right = header.left + header.width;
    final hit = direction == TextDirection.ltr
        ? Rect.fromLTRB(
            right - hitWidth,
            header.top,
            right,
            header.top + header.height,
          )
        : Rect.fromLTRB(
            header.left,
            header.top,
            header.left + hitWidth,
            header.top + header.height,
          );
    return (hit: hit, label: labelParagraph, icon: iconParagraph, width: width);
  }

  /// The laid-out paragraph of [text] in [style] across [width], from the
  /// bounded cache. [align] null is the start edge of [direction].
  ui.Paragraph _paragraph(
    String text,
    TextStyle style, {
    required double width,
    TextDirection direction = TextDirection.ltr,
    TextAlign? align,
  }) => _textParagraphs.obtain(
    _TextPaintKey(
      text: text,
      style: style,
      width: width,
      direction: direction,
      align: align,
    ),
    () {
      final builder =
          ui.ParagraphBuilder(
              style.getParagraphStyle(
                textScaler: TextScaler.noScaling,
                textAlign: align,
                textDirection: direction,
              ),
            )
            ..pushStyle(style.getTextStyle())
            ..addText(text);
      return builder.build()..layout(ui.ParagraphConstraints(width: width));
    },
  );

  /// Paints the empty-message row of a loaded section with nothing in it:
  /// [CatalogMessageSlot.text] in the header style at regular weight, centred
  /// across the section's usable width and in the row's height.
  void paintMessage({
    required Canvas canvas,
    required Offset origin,
    required CatalogMessageSlot slot,
  }) {
    final inset = _theme.sectionHeaderStartInset;
    final width = math.max<double>(0, slot.width - 2 * inset);
    final paragraph = _paragraph(
      slot.text,
      _messageStyle,
      width: width,
      align: TextAlign.center,
    );
    canvas.drawParagraph(
      paragraph,
      Offset(
        origin.dx + slot.left + inset,
        origin.dy + slot.top + (slot.height - paragraph.height) / 2,
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
  ///
  /// [hovered] paints the theme's hover wash (inset, rounded) under everything
  /// else of the cell; nothing without a hover token.
  void paintLeaf({
    required Canvas canvas,
    required Offset origin,
    required CatalogLeafSlot slot,
    required CatalogBoundLeaf? bound,
    double pressScale = 1,
    double pressProgress = 0,
    bool focused = false,
    bool hovered = false,
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

    // Under the content like the press wash: a sprite is queued and drawn at
    // the end of the pass, over everything painted here.
    final hover = theme.leafHoverHighlightColor;
    if (hovered && hover != null && hover.a > 0) {
      final box = switch (theme.leafHoverHighlightSize) {
        final size? => Rect.fromCenter(
          center: cellRect.center,
          width: math.min(size.width, cellRect.width),
          height: math.min(size.height, cellRect.height),
        ),
        null => cellRect.deflate(theme.leafHoverHighlightInset),
      };
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          box,
          Radius.circular(theme.leafHoverHighlightRadius),
        ),
        _highlightPaint..color = hover,
      );
    }
    if (focused && theme.leafFocusHighlightColor.a > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          cellRect,
          Radius.circular(theme.leafPressSelectorRadius),
        ),
        _highlightPaint..color = theme.leafFocusHighlightColor,
      );
    }
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
        if (slot.leaf.key case ContentKey$Unicode()) {
          PanelCatalogDiagnostics.glyphParagraphDraws++;
        }
        binding!.paint(canvas, glyphRect, opacity: opacity);
    }

    if (scaled) {
      canvas.restore();
    }
  }

  /// Paints one skeleton cell: the stand-in of its style in its content box, in
  /// the skeleton colour (the sticker wash keeps its sweep, so a loading
  /// sticker section shimmers like a loading sticker).
  ///
  /// Reads no binding and asks no cache for anything.
  void paintSkeleton({
    required Canvas canvas,
    required Offset origin,
    required CatalogSkeletonSlot slot,
  }) {
    final cellRect = Rect.fromLTWH(
      origin.dx + slot.left,
      origin.dy + slot.top,
      slot.width,
      slot.height,
    );
    final side = slot.contentExtent;
    final box = Rect.fromCenter(
      center: cellRect.center,
      width: side,
      height: side,
    );
    switch (slot.style) {
      case CatalogPlaceholderStyle.circle:
        canvas.drawCircle(
          box.center,
          box.width * kCirclePlaceholderRadiusFactor,
          _skeletonPaint,
        );
      case CatalogPlaceholderStyle.thumbFirst:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            box,
            Radius.circular(_theme.placeholderCornerRadius),
          ),
          _skeletonPaint,
        );
      case CatalogPlaceholderStyle.shapedWash:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            box,
            Radius.circular(_theme.placeholderCornerRadius),
          ),
          _wash(),
        );
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
    final band = math.max<double>(1, _viewport.width * 0.5);
    final start = _viewport.left - band + phase * (_viewport.width + band);
    return ui.Gradient.linear(
      Offset(start, 0),
      Offset(start + band, 0),
      [theme.washColor, theme.washHighlightColor, theme.washColor],
      const [0, 0.5, 1],
    );
  }
}

/// Cache key for the painter's text paragraphs: header titles, action labels
/// and icons, and empty messages (text, style, layout width, alignment).
@immutable
final class _TextPaintKey {
  const _TextPaintKey({
    required this.text,
    required this.style,
    required this.width,
    required this.direction,
    required this.align,
  });

  final String text;
  final TextStyle style;
  final double width;
  final TextDirection direction;
  final TextAlign? align;

  @override
  bool operator ==(Object other) =>
      other is _TextPaintKey &&
      other.text == text &&
      other.style == style &&
      other.width == width &&
      other.direction == direction &&
      other.align == align;

  @override
  int get hashCode => Object.hash(text, style, width, direction, align);
}
