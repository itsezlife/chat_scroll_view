import 'dart:math' as math;

import 'package:chat_scroll_view/src/chat_scroll/chat_selection_policy.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_md/flutter_md.dart';

// --- Host labels -----------------------------------------------------------

/// Host-owned copy for fenced-code chrome (package stays locale-agnostic).
@immutable
class ChatCodeBlockLabels {
  /// Creates labels. Prefer app l10n; English defaults are for tests/demos.
  const ChatCodeBlockLabels({
    this.copyCode = 'COPY CODE',
    this.untitled = 'CODE',
  });

  /// English defaults (tests / demos without l10n).
  static const ChatCodeBlockLabels english = ChatCodeBlockLabels();

  /// Mobile bottom-bar / desktop untitled-header copy affordance.
  final String copyCode;

  /// Desktop header when the fence has no language tag.
  final String untitled;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatCodeBlockLabels &&
          copyCode == other.copyCode &&
          untitled == other.untitled;

  @override
  int get hashCode => Object.hash(copyCode, untitled);
}

/// Ambient [ChatCodeBlockLabels] for descendant [ChatMarkdownBody] mounts.
class ChatCodeBlockLabelsScope extends InheritedWidget {
  /// Installs [labels] for the subtree.
  const ChatCodeBlockLabelsScope({
    required this.labels,
    required super.child,
    super.key,
  });

  /// Host chrome strings.
  final ChatCodeBlockLabels labels;

  /// Nearest labels, or [ChatCodeBlockLabels.english] when none.
  static ChatCodeBlockLabels of(BuildContext context) =>
      maybeOf(context) ?? ChatCodeBlockLabels.english;

  /// Nearest labels, or null.
  static ChatCodeBlockLabels? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<ChatCodeBlockLabelsScope>()
      ?.labels;

  @override
  bool updateShouldNotify(covariant ChatCodeBlockLabelsScope oldWidget) =>
      labels != oldWidget.labels;
}

// --- Builder helper --------------------------------------------------------

/// Custom block painter builder for fenced markdown code blocks.
///
/// Can be plugged into [MarkdownThemeData.builder] to render fenced code blocks
/// with separated interactive header/bottom bars and offset text selection
/// coordinates.
BlockPainter? chatCodeBlockBuilder(
  MD$Block block,
  MarkdownThemeData theme, {
  ChatSelectionPolicy? policy,
  ChatCodeBlockLabels labels = ChatCodeBlockLabels.english,
}) {
  if (block case MD$Code(:final text, :final language)) {
    return ChatCodeBlockPainter(
      text: text,
      language: language,
      theme: theme,
      policy: policy,
      labels: labels,
    );
  }
  return null;
}

// --- ChatCodeBlockPainter --------------------------------------------------

/// A custom [BlockPainter] that separates interactive code block chrome
/// (desktop click-to-copy header or mobile bottom copy bar) from the selectable
/// code body text.
///
/// Implements [SelectableTextBlock] so that text selection carets, bounding
/// boxes, and drag gestures align 100% pixel-accurately with the code text by
/// offsetting [selectionOrigin] by [outerPadding], [headerHeight], and
/// [padding].
///
/// ## Platform Interaction Matrix
///
/// Under [ChatSelectionPolicy$Desktop]:
/// - A top header bar is rendered with the programming language name and a
///   trailing copy button.
/// - Hovering or tapping over the top header bar reports `isLinkAtLocal == true`,
///   displaying [SystemMouseCursors.click] and routing taps to click-to-copy.
/// - The code body beneath it reports `isLinkAtLocal == false`, presenting
///   [SystemMouseCursors.text] and supporting character/word text selection.
/// - No bottom bar is rendered.
///
/// Under [ChatSelectionPolicy$Mobile]:
/// - A top header bar displays an informative (non-tappable) language label.
///   `isLinkAtLocal` returns `false` over the top header.
/// - If the code snippet contains at least
///   [ChatSelectionPolicy.mobileCodeCopyBarThreshold] (75) characters, an
///   interactive bottom "COPY CODE" bar is rendered. Tapping this bar reports
///   `isLinkAtLocal == true` to trigger click-to-copy.
/// - Code bodies support mobile text selection entry via long-press without
///   interference from the header chrome.
class ChatCodeBlockPainter with SelectableTextBlock implements BlockPainter {
  /// Creates a fenced code block painter.
  factory ChatCodeBlockPainter({
    required String text,
    required String? language,
    required MarkdownThemeData theme,
    ChatSelectionPolicy? policy,
    ChatCodeBlockLabels labels = ChatCodeBlockLabels.english,
  }) {
    final resolvedPolicy = policy ?? ChatSelectionPolicy.forPlatform();
    final background =
        theme.highlighter?.backgroundFor(language) ??
        theme.surfaceColor ??
        const Color(0xFF1E1E22);
    final chromeInk = fenceChromeInk(background);
    return ChatCodeBlockPainter._(
      text: text,
      language: language,
      theme: theme,
      policy: resolvedPolicy,
      labels: labels,
      background: background,
      headerBackground: fenceChromeWash(background),
      dividerColor: theme.dividerColor ?? chromeInk.withValues(alpha: 0.14),
      iconColor: chromeInk.withValues(alpha: 0.7),
      chromeInk: chromeInk,
    );
  }

  ChatCodeBlockPainter._({
    required this.text,
    required this.language,
    required this.theme,
    required this.policy,
    required this.labels,
    required Color background,
    required Color headerBackground,
    required Color dividerColor,
    required Color iconColor,
    required Color chromeInk,
  }) : _background = background,
       _headerBackground = headerBackground,
       _dividerColor = dividerColor,
       _iconColor = iconColor,
       painter = TextPainter(
         text: _buildCodeSpan(text, language, theme),
         textAlign: TextAlign.start,
         textDirection: theme.textDirection,
         textScaler: theme.textScaler,
       ),
       _headerPainter = _buildHeaderPainter(
         language,
         theme,
         policy,
         chromeInk,
         labels,
       ),
       _bottomBarPainter = _buildBottomBarPainter(text, theme, policy, labels);

  /// Host chrome strings (copy bar / untitled language).
  final ChatCodeBlockLabels labels;

  /// Ink used for header/footer labels and washes on [fenceBackground].
  ///
  /// Keys off fence luminance — not bubble [MarkdownThemeData.textStyle] —
  /// so dark highlighters (GitHub dark) still get a light chrome strip.
  @visibleForTesting
  static Color fenceChromeInk(Color fenceBackground) =>
      fenceBackground.computeLuminance() > 0.45
      ? const Color(0xFF000000)
      : const Color(0xFFFFFFFF);

  /// Header / bottom-bar fill on top of [fenceBackground].
  @visibleForTesting
  static Color fenceChromeWash(Color fenceBackground) {
    final ink = fenceChromeInk(fenceBackground);
    final alpha = fenceBackground.computeLuminance() > 0.45 ? 0.08 : 0.12;
    return ink.withValues(alpha: alpha);
  }

  // --- Geometry Constants --------------------------------------------------

  /// Internal padding around the code text (inside the fence fill).
  static const double padding = 12;

  /// Unpainted vertical padding above and below the fence fill.
  static const double outerPadding = 4;

  /// Height of the interactive top header bar on desktop.
  static const double desktopHeaderHeight = 32;

  /// Height of the informative top header bar on mobile.
  static const double mobileHeaderHeight = 26;

  /// Height of the interactive bottom copy bar on mobile.
  static const double mobileBottomBarHeight = 36;

  // --- Properties ----------------------------------------------------------

  /// The raw code string contained in the fenced code block.
  final String text;

  /// Optional language identifier parsed from the code fence opening line.
  final String? language;

  /// Markdown styling theme.
  final MarkdownThemeData theme;

  /// Cross-platform selection policy governing chrome interactivity.
  final ChatSelectionPolicy policy;

  /// Text painter that formats and paints the code body glyphs.
  final TextPainter painter;

  final TextPainter? _headerPainter;
  final TextPainter? _bottomBarPainter;

  final Color _background;
  final Color _headerBackground;
  final Color _dividerColor;
  final Color _iconColor;

  Size _size = Size.zero;

  // --- Header & Bottom Bar State -------------------------------------------

  /// Whether a top header bar is rendered for this block.
  ///
  /// On desktop, a header is always rendered to host the copy button.
  /// On mobile, an informative header is rendered when [language] is non-empty.
  bool get hasHeader {
    if (policy.hasInteractiveCodeHeader) return true;
    return switch (language) {
      final l? when l.trim().isNotEmpty => true,
      _ => false,
    };
  }

  /// Height of the top header bar, or `0.0` if no header is rendered.
  double get headerHeight {
    if (!hasHeader) return 0;
    return policy.hasInteractiveCodeHeader
        ? desktopHeaderHeight
        : mobileHeaderHeight;
  }

  /// Whether an interactive bottom copy bar is rendered for this block.
  bool get hasBottomBar => policy.hasBottomCodeCopyBarForLength(text.length);

  /// Height of the bottom copy bar, or `0.0` if no bottom bar is rendered.
  double get bottomBarHeight => hasBottomBar ? mobileBottomBarHeight : 0.0;

  /// Height of the painted fence (header + body + optional bottom bar),
  /// excluding [outerPadding] on both ends.
  double get paintedHeight =>
      math.max<double>(0, _size.height - outerPadding * 2);

  /// Top edge of the painted fence in local block coordinates.
  double get paintedTop => outerPadding;

  /// Bottom edge of the painted fence in local block coordinates.
  double get paintedBottom => paintedTop + paintedHeight;

  // --- SelectableTextBlock Protocol ----------------------------------------

  @override
  TextPainter get selectionPainter => painter;

  /// Shifted origin for text selection coordinates.
  ///
  /// Anchors text selection to the code body's top-left corner, shifted down
  /// by [outerPadding], [headerHeight], and [padding]. This prevents vertical
  /// caret and drag handle drift across the code block.
  @override
  Offset get selectionOrigin =>
      Offset(padding, outerPadding + headerHeight + padding);

  /// Selection highlights must be painted above the cached content picture
  /// so that the opaque background fill does not obscure the highlight.
  @override
  bool get selectionHighlightAboveCachedContent => true;

  @override
  bool isLinkAtLocal(Offset local) {
    final top = paintedTop;
    final bottom = paintedBottom;
    if (local.dx < 0 ||
        local.dx > _size.width ||
        local.dy < top ||
        local.dy >= bottom) {
      return false;
    }
    // Interactive top header on desktop
    if (hasHeader &&
        policy.hasInteractiveCodeHeader &&
        local.dy < top + headerHeight) {
      return true;
    }
    // Interactive bottom copy bar on mobile
    if (hasBottomBar && local.dy >= bottom - bottomBarHeight) {
      return true;
    }
    return false;
  }

  // --- BlockPainter Protocol -----------------------------------------------

  @override
  Size get size => _size;

  @override
  void handleTapDown(PointerDownEvent event) {
    // Arbitrated by viewport pointer gestures and ChatTextSelection.
  }

  @override
  void handleTapUp(PointerUpEvent event) {
    // Arbitrated by viewport pointer gestures and ChatTextSelection.
  }

  @override
  Size layout(double width) {
    if (width <= padding * 2) {
      return _size = Size.zero;
    }
    final contentWidth = width - padding * 2;
    painter.layout(minWidth: 0, maxWidth: contentWidth);

    final hHeight = headerHeight;
    if (hasHeader && _headerPainter != null) {
      final headerContentWidth = policy.hasInteractiveCodeHeader
          ? math.max<double>(
              0,
              contentWidth - 36.0,
            ) // reserve room for copy button
          : contentWidth;
      _headerPainter.layout(minWidth: 0, maxWidth: headerContentWidth);
    }

    if (hasBottomBar && _bottomBarPainter != null) {
      _bottomBarPainter.layout(minWidth: 0, maxWidth: contentWidth);
    }

    final totalHeight =
        outerPadding +
        hHeight +
        padding +
        painter.size.height +
        padding +
        bottomBarHeight +
        outerPadding;
    final totalWidth = width.isFinite
        ? width
        : painter.size.width + padding * 2;
    return _size = Size(totalWidth, totalHeight);
  }

  @override
  void paint(Canvas canvas, Size size, double offset) {
    if (size.width < _size.width) return;
    final fillTop = offset + paintedTop;
    final fillHeight = paintedHeight;
    final blockRect = Rect.fromLTWH(0, fillTop, size.width, fillHeight);
    const cornerRadius = Radius.circular(8);
    final rrect = RRect.fromRectAndRadius(blockRect, cornerRadius);

    // 1. Block background (excludes outerPadding bands)
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = _background
        ..style = PaintingStyle.fill,
    );

    // 2. Top header bar
    final hHeight = headerHeight;
    if (hasHeader) {
      final headerRect = Rect.fromLTWH(0, fillTop, size.width, hHeight);
      final headerRRect = RRect.fromRectAndCorners(
        headerRect,
        topLeft: cornerRadius,
        topRight: cornerRadius,
      );

      canvas.drawRRect(
        headerRRect,
        Paint()
          ..color = _headerBackground
          ..style = PaintingStyle.fill,
      );

      // Divider line under header
      canvas.drawLine(
        Offset(0, fillTop + hHeight),
        Offset(size.width, fillTop + hHeight),
        Paint()
          ..color = _dividerColor
          ..strokeWidth = 1.0,
      );

      // Language label
      if (_headerPainter != null) {
        final textY = fillTop + (hHeight - _headerPainter.height) / 2;
        _headerPainter.paint(canvas, Offset(padding + 4.0, textY));
      }

      // Desktop copy icon
      if (policy.hasInteractiveCodeHeader) {
        _paintCopyIcon(canvas, size.width, fillTop, hHeight);
      }
    }

    // 3. Code body text
    painter.paint(canvas, Offset(padding, fillTop + hHeight + padding));

    // 4. Mobile bottom copy bar
    if (hasBottomBar) {
      final bHeight = bottomBarHeight;
      final bottomBarY = fillTop + fillHeight - bHeight;
      final bottomBarRect = Rect.fromLTWH(0, bottomBarY, size.width, bHeight);
      final bottomBarRRect = RRect.fromRectAndCorners(
        bottomBarRect,
        bottomLeft: cornerRadius,
        bottomRight: cornerRadius,
      );

      canvas.drawRRect(
        bottomBarRRect,
        Paint()
          ..color = _headerBackground
          ..style = PaintingStyle.fill,
      );

      // Divider line above bottom bar
      canvas.drawLine(
        Offset(0, bottomBarY),
        Offset(size.width, bottomBarY),
        Paint()
          ..color = _dividerColor
          ..strokeWidth = 1.0,
      );

      // Bottom bar label centered
      if (_bottomBarPainter != null) {
        final textX = (size.width - _bottomBarPainter.width) / 2;
        final textY = bottomBarY + (bHeight - _bottomBarPainter.height) / 2;
        _bottomBarPainter.paint(canvas, Offset(textX, textY));
      }
    }
  }

  void _paintCopyIcon(
    Canvas canvas,
    double width,
    double blockOffset,
    double hHeight,
  ) {
    const iconWidth = 12.0;
    const iconHeight = 13.0;
    final iconX = width - padding - 16.0;
    final iconY = blockOffset + (hHeight - iconHeight) / 2;

    final strokePaint = Paint()
      ..color = _iconColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeJoin = StrokeJoin.round;

    final fillPaint = Paint()
      ..color = _background
      ..style = PaintingStyle.fill;

    // Back card (offset slightly up-right)
    final backRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        iconX + 3.0,
        iconY - 1.0,
        iconWidth - 2.5,
        iconHeight - 2.5,
      ),
      const Radius.circular(2),
    );
    canvas.drawRRect(backRect, strokePaint);

    // Front card (drawn on top with fill to mask back card)
    final frontRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(iconX, iconY + 2.0, iconWidth - 2.5, iconHeight - 2.5),
      const Radius.circular(2),
    );
    canvas.drawRRect(frontRect, fillPaint);
    canvas.drawRRect(frontRect, strokePaint);
  }

  @override
  void dispose() {
    painter.dispose();
    _headerPainter?.dispose();
    _bottomBarPainter?.dispose();
  }

  // --- Static Text Building Helpers ----------------------------------------

  static TextSpan _buildCodeSpan(
    String text,
    String? language,
    MarkdownThemeData theme,
  ) {
    final baseStyle = theme.textStyle.copyWith(
      fontFamily: 'monospace',
      fontSize: theme.textStyle.fontSize ?? 13.0,
      height: 1.35,
    );
    final highlighter = theme.highlighter;
    if (highlighter == null) return TextSpan(text: text, style: baseStyle);
    final effectiveBase = highlighter.baseStyleFor(language, baseStyle);
    return TextSpan(
      style: effectiveBase,
      children: highlighter.highlight(text, language, effectiveBase),
    );
  }

  static TextPainter? _buildHeaderPainter(
    String? language,
    MarkdownThemeData theme,
    ChatSelectionPolicy policy,
    Color chromeInk,
    ChatCodeBlockLabels labels,
  ) {
    final label = switch (language) {
      final l? when l.trim().isNotEmpty => l.trim().toUpperCase(),
      _ => policy.hasInteractiveCodeHeader ? labels.untitled.toUpperCase() : '',
    };
    if (label.isEmpty) return null;

    final style = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.5,
      color: chromeInk.withValues(alpha: 0.7),
      fontFamily: theme.textStyle.fontFamily,
    );

    return TextPainter(
      text: TextSpan(text: label, style: style),
      textDirection: theme.textDirection,
      textScaler: theme.textScaler,
    );
  }

  static TextPainter? _buildBottomBarPainter(
    String text,
    MarkdownThemeData theme,
    ChatSelectionPolicy policy,
    ChatCodeBlockLabels labels,
  ) {
    if (!policy.hasBottomCodeCopyBarForLength(text.length)) {
      return null;
    }

    final accent = theme.linkColor ?? const Color(0xFF58A6FF);
    final style = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.8,
      color: accent,
      fontFamily: theme.textStyle.fontFamily,
    );

    return TextPainter(
      text: TextSpan(text: labels.copyCode.toUpperCase(), style: style),
      textDirection: theme.textDirection,
      textScaler: theme.textScaler,
    );
  }
}
