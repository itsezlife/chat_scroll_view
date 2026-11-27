import 'dart:math' as math;

import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/widgets.dart' hide RichText;
import 'package:message_media/src/diagnostics/link_preview_card_op.dart';
import 'package:message_media/src/layout/link_preview_card.dart';
import 'package:message_media/src/layout/media_layout.dart';
import 'package:message_media/src/policy/link_preview_card_policy.dart';
import 'package:meta/meta.dart';

/// The colours a link preview card is drawn in: the host's, since the
/// accent is the sender's colour on an incoming message and the bubble's
/// accent on an outgoing one.
@immutable
final class LinkPreviewCardColors {
  /// Colours of [accent] (the bar, the fill, the site name, links) and
  /// [text] (the title and the description).
  const LinkPreviewCardColors({
    required this.accent,
    this.text,
    this.outgoing = false,
    this.dark = false,
  });

  /// The fallback: a blue accent, the ambient text colour.
  static const fallback = LinkPreviewCardColors(accent: Color(0xFF3390EC));

  /// The bar, the fill (at the block style's share), the site name, the
  /// links and the button.
  final Color accent;

  /// The title and description; null is the ambient text colour.
  final Color? text;

  /// Whether the message is outgoing (the fill's share may differ).
  final bool outgoing;

  /// Whether the theme is dark (the fill's share may differ).
  final bool dark;

  @override
  bool operator ==(Object other) =>
      other is LinkPreviewCardColors &&
      other.accent == accent &&
      other.text == text &&
      other.outgoing == outgoing &&
      other.dark == dark;

  @override
  int get hashCode => Object.hash(accent, text, outgoing, dark);
}

/// A link under a point of a card's description.
@internal
typedef LinkPreviewCardLink = ({String url, String title, Path contour});

/// Draws one link preview card: the tinted block with its bar, the text,
/// the button, the desktop enlarge button and the card's media cell
/// ([media], built by the media path at the cell's place in the card).
///
/// The press feedback is the policy's over `ChromeInk`, yielding the tap to
/// the viewport (which arbitrates it as a body part hit), and never under a
/// link, the button or the media. Every rect it draws comes from the
/// card's layout, so what the viewport hits is what is drawn.
///
/// Reports `linkPreview` / `cardShown` once per page.
@internal
class LinkPreviewCardView extends StatefulWidget {
  /// The card of [block].
  const LinkPreviewCardView({
    required this.block,
    required this.card,
    required this.policy,
    required this.colors,
    this.media,
    this.pressable = true,
    this.correlation = ChatCorrelation.none,
    super.key,
  });

  /// The block, whose rect the card is drawn relative to.
  final MediaBlock$LinkPreview block;

  /// The card's geometry.
  final LinkPreviewCard card;

  /// The card's policy.
  final LinkPreviewCardPolicy policy;

  /// The colours.
  final LinkPreviewCardColors colors;

  /// The media cell, positioned in the card's coordinates.
  final Widget? media;

  /// Whether presses show (not in message selection).
  final bool pressable;

  /// The ids the card's event names.
  final ChatCorrelation correlation;

  @override
  State<LinkPreviewCardView> createState() => LinkPreviewCardViewState();
}

/// The card's state: its description layout, for link hits.
@internal
class LinkPreviewCardViewState extends State<LinkPreviewCardView> {
  TextPainter? _description;

  @override
  void initState() {
    super.initState();
    _reportShown();
  }

  @override
  void didUpdateWidget(LinkPreviewCardView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.block.page.url != widget.block.page.url) _reportShown();
    if (oldWidget.block.page.description != widget.block.page.description ||
        oldWidget.card != widget.card ||
        oldWidget.colors != widget.colors) {
      _description?.dispose();
      _description = null;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _description?.dispose();
    _description = null;
  }

  @override
  void dispose() {
    _description?.dispose();
    super.dispose();
  }

  void _reportShown() {
    final card = widget.card;
    ChatDiagnostics.current.emit(
      ChatEventLevel.debug,
      ChatEventCategory.linkPreview,
      LinkPreviewCardOp.cardShown,
      correlation: ChatCorrelation(
        chatId: widget.correlation.chatId,
        scrollId: widget.correlation.scrollId,
        clientMessageId: widget.correlation.clientMessageId,
      ),
      fields: () => {
        'size': card.mediaSize?.name ?? 'none',
        'widthRule': card.width.name,
        'appear': card.appear.name,
      },
    );
  }

  TextStyle _base(BuildContext context) => ChromeTypography.of(context);

  Color _textColor(BuildContext context) =>
      widget.colors.text ??
      DefaultTextStyle.of(context).style.color ??
      const Color(0xFF000000);

  /// The link of the description under [layoutPoint] (layout coordinates),
  /// with its contour in layout coordinates; null when none is there.
  LinkPreviewCardLink? linkAt(Offset layoutPoint) {
    final piece = widget.card.pieceOf(LinkPreviewCardPart.description);
    if (piece == null || !piece.rect.contains(layoutPoint) || !mounted) {
      return null;
    }
    final description = widget.block.page.description;
    final hasLinks = description.entities.any(
      (entity) => switch (entity.kind) {
        EntityKind$Link() => true,
        _ => false,
      },
    );
    if (!hasLinks) return null;
    final painter = _description ??= _descriptionPainter(context, piece);
    final local = layoutPoint - piece.rect.topLeft;
    final offset = painter.getPositionForOffset(local).offset;
    for (final entity in description.entities) {
      if (entity.kind case EntityKind$Link(
        :final url,
      ) when offset >= entity.offset && offset < entity.end) {
        final boxes = painter.getBoxesForSelection(
          TextSelection(baseOffset: entity.offset, extentOffset: entity.end),
        );
        if (!boxes.any((box) => box.toRect().inflate(2).contains(local))) {
          return null;
        }
        final contour = Path();
        for (final box in boxes) {
          contour.addRect(box.toRect().shift(piece.rect.topLeft));
        }
        return (
          url: url,
          title: description.plain.substring(entity.offset, entity.end),
          contour: contour,
        );
      }
    }
    return null;
  }

  TextPainter _descriptionPainter(
    BuildContext context,
    LinkPreviewCardPiece piece,
  ) => TextPainter(
    text: _span(context, LinkPreviewCardPart.description),
    textDirection: Directionality.of(context),
    maxLines: piece.maxLines,
    ellipsis: '…',
  )..layout(maxWidth: piece.rect.width);

  InlineSpan _span(BuildContext context, LinkPreviewCardPart part) {
    final page = widget.block.page;
    final type = widget.policy.text;
    final base = _base(context);
    final text = _textColor(context);
    final accent = widget.colors.accent;
    return switch (part) {
      LinkPreviewCardPart.siteName => TextSpan(
        text: page.siteName,
        style: type.over(base, weight: type.siteWeight).copyWith(color: accent),
      ),
      LinkPreviewCardPart.title => TextSpan(
        text: page.title,
        style: type.over(base, weight: type.titleWeight).copyWith(color: text),
      ),
      LinkPreviewCardPart.author => TextSpan(
        text: page.author,
        style: type.over(base).copyWith(color: text),
      ),
      LinkPreviewCardPart.description => linkPreviewDescriptionSpan(
        page.description,
        type.over(base).copyWith(color: text),
        linkColor: accent,
      ),
    };
  }

  /// Whether a press at [local] (card coordinates) presses the card: not
  /// on a link, the button, the media or the enlarge button.
  bool _pressableAt(Offset local) {
    if (!widget.pressable) return false;
    final card = widget.card;
    final point = local + card.rect.topLeft;
    if (card.button?.rect.contains(point) ?? false) return false;
    if (card.enlarge?.contains(point) ?? false) return false;
    if (widget.block.media?.rect.contains(point) ?? false) return false;
    return linkAt(point) == null;
  }

  @override
  Widget build(BuildContext context) {
    final card = widget.card;
    final policy = widget.policy;
    final colors = widget.colors;
    final origin = card.rect.topLeft;
    final style = policy.style;
    final fill = colors.accent.withValues(
      alpha:
          colors.accent.a *
          style.fillOpacityFor(outgoing: colors.outgoing, dark: colors.dark),
    );
    final press = policy.press;
    final ripple = press.kind == ChromeInkKind.pointer
        ? fill
        : colors.accent.withValues(
            alpha: colors.accent.a * press.rippleOpacity,
          );
    final textAlign = card.rtl ? TextAlign.right : TextAlign.left;
    Rect local(Rect rect) => rect.shift(-origin);
    return SizedBox.fromSize(
      size: card.rect.size,
      child: ChromeInk(
        kind: press.kind,
        color: ripple,
        borderRadius: press.rippleRadius,
        scale: press.cardScale,
        onTap: null,
        yieldsTap: true,
        pressableAt: _pressableAt,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _BlockPainter(
                  fill: fill,
                  bar: colors.accent,
                  barWidth: style.barWidth,
                  radius: style.radius,
                  barOnRight: card.rtl,
                ),
              ),
            ),
            for (final piece in card.texts)
              Positioned.fromRect(
                rect: local(piece.rect),
                // The card's node speaks the text (the body's semantics).
                child: ExcludeSemantics(
                  child: Text.rich(
                    _span(context, piece.part),
                    // The ambient style (its line height) never reaches the
                    // card: the layout measured without it.
                    style: _base(context),
                    maxLines: piece.maxLines,
                    overflow: TextOverflow.ellipsis,
                    textAlign: textAlign,
                    textScaler: TextScaler.noScaling,
                  ),
                ),
              ),
            ?widget.media,
            if (card.enlarge case final enlarge?)
              Positioned.fromRect(
                rect: local(enlarge),
                child: IgnorePointer(
                  child: _EnlargeButton(radius: policy.enlarge?.radius ?? 8),
                ),
              ),
            if (card.button case final button?)
              Positioned.fromRect(
                rect: local(button.rect),
                child: _CardButton(
                  label: button.label,
                  policy: policy,
                  colors: colors,
                  textColor: _textColor(context),
                  base: _base(context),
                  pressable: widget.pressable,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CardButton extends StatelessWidget {
  const _CardButton({
    required this.label,
    required this.policy,
    required this.colors,
    required this.textColor,
    required this.base,
    required this.pressable,
  });

  final String label;
  final LinkPreviewCardPolicy policy;
  final LinkPreviewCardColors colors;
  final Color textColor;
  final TextStyle base;
  final bool pressable;

  @override
  Widget build(BuildContext context) {
    final m = policy.metrics;
    final accent = colors.accent;
    final dividerColor = switch (policy.press.kind) {
      // Android's hairline is the text colour's; desktop's the accent's.
      ChromeInkKind.ripple => textColor,
      _ => accent,
    };
    final press = policy.press;
    return ChromeInk(
      kind: press.kind,
      color: accent.withValues(
        alpha: accent.a * math.max(press.rippleOpacity, 0),
      ),
      borderRadius: press.rippleRadius,
      scale: press.buttonScale,
      onTap: null,
      yieldsTap: true,
      pressableAt: (_) => pressable,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: policy.press.kind == ChromeInkKind.highlight
              ? accent.withValues(alpha: accent.a * policy.style.fillOpacity)
              : null,
          borderRadius: policy.press.kind == ChromeInkKind.highlight
              ? BorderRadius.circular(policy.style.radius)
              : null,
          border: m.buttonDividerWidth > 0
              ? Border(
                  top: BorderSide(
                    width: m.buttonDividerWidth,
                    color: dividerColor.withValues(
                      alpha: dividerColor.a * m.buttonDividerOpacity,
                    ),
                  ),
                )
              : null,
        ),
        child: Padding(
          padding: m.buttonPadding,
          // The body gives the button a node of its own.
          child: ExcludeSemantics(
            child: Center(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textScaler: TextScaler.noScaling,
                style: policy.text.buttonOver(base).copyWith(color: accent),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The enlarge button: a dark rounded square with two diagonal arrows.
class _EnlargeButton extends StatelessWidget {
  const _EnlargeButton({required this.radius});

  final double radius;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0x66000000),
      borderRadius: BorderRadius.circular(radius),
    ),
    child: const CustomPaint(painter: _EnlargeGlyph()),
  );
}

class _EnlargeGlyph extends CustomPainter {
  const _EnlargeGlyph();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    final inset = size.shortestSide * 0.3;
    final a = Offset(inset, size.height - inset);
    final b = Offset(size.width - inset, inset);
    final arm = size.shortestSide * 0.18;
    canvas
      ..drawLine(a, b, paint)
      ..drawLine(b, b + Offset(-arm, 0), paint)
      ..drawLine(b, b + Offset(0, arm), paint)
      ..drawLine(a, a + Offset(arm, 0), paint)
      ..drawLine(a, a + Offset(0, -arm), paint);
  }

  @override
  bool shouldRepaint(_EnlargeGlyph oldDelegate) => false;
}

class _BlockPainter extends CustomPainter {
  const _BlockPainter({
    required this.fill,
    required this.bar,
    required this.barWidth,
    required this.radius,
    required this.barOnRight,
  });

  final Color fill;
  final Color bar;
  final double barWidth;
  final double radius;
  final bool barOnRight;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final block = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    canvas
      ..save()
      ..clipRRect(block)
      ..drawRect(rect, Paint()..color = fill)
      ..drawRect(
        barOnRight
            ? Rect.fromLTWH(size.width - barWidth, 0, barWidth, size.height)
            : Rect.fromLTWH(0, 0, barWidth, size.height),
        Paint()..color = bar,
      )
      ..restore();
  }

  @override
  bool shouldRepaint(_BlockPainter oldDelegate) =>
      oldDelegate.fill != fill ||
      oldDelegate.bar != bar ||
      oldDelegate.barWidth != barWidth ||
      oldDelegate.radius != radius ||
      oldDelegate.barOnRight != barOnRight;
}
