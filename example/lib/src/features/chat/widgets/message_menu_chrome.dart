import 'dart:math' as math;

import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// How the message menu looks and moves in the app's chrome, per platform
/// family: the builders the host hands `ChatMessageMenu.show`.
///
/// On Android a sheet menu takes the chrome's own rows ([MessageMenuRow])
/// on the message menu glass ([GlassMaterial.messageMenu]), its reaction
/// strip on the same glass coming in on its own ([MessageMenuStripEnter]);
/// the menu pops up from its bottom right corner (it hangs left of the
/// press). On a desktop a popup
/// takes the pointer menu's rows with icons ([MessageMenuPointerRow]) on its
/// solid card ([desktopSurface]), and grows from the corner at the pointer. Elsewhere the rows and the card are the package's and a sheet
/// plays the platform's appear motion.
abstract final class MessageMenuChrome {
  /// Whether a menu of [presentation] takes the Android chrome on this
  /// platform.
  static bool isAndroidSheet(ChatMessageMenuPresentation presentation) =>
      presentation == ChatMessageMenuPresentation.sheet &&
      ChromeInkKind.forPlatform(defaultTargetPlatform) == ChromeInkKind.ripple;

  /// Whether a menu of [presentation] takes the desktop chrome on this
  /// platform.
  static bool isDesktopPopup(ChatMessageMenuPresentation presentation) =>
      presentation == ChatMessageMenuPresentation.popup &&
      ChromeInkKind.forPlatform(defaultTargetPlatform) == ChromeInkKind.pointer;

  /// The rows of a menu of [presentation], or null for the package's.
  static ChatMessageMenuItemBuilder? itemBuilderFor(
    ChatMessageMenuPresentation presentation,
  ) => switch (presentation) {
    _ when isAndroidSheet(presentation) =>
      (context, item, onSelect) => MessageMenuRow(item: item, onTap: onSelect),
    _ when isDesktopPopup(presentation) =>
      (context, item, onSelect) =>
          MessageMenuPointerRow(item: item, onTap: onSelect),
    _ => null,
  };

  /// The action card's surface for [presentation], or null for the
  /// package's.
  static ChatMessageMenuSurfaceBuilder? surfaceBuilderFor(
    ChatMessageMenuPresentation presentation,
  ) => switch (presentation) {
    _ when isAndroidSheet(presentation) => surface,
    _ when isDesktopPopup(presentation) => desktopSurface,
    _ => null,
  };

  /// The message menu glass around [child]: the action card's rows, or the
  /// reaction strip, which comes in on its own ([MessageMenuStripEnter]).
  static Widget surface(
    BuildContext context,
    ChatMessageMenuSurface surface,
    Widget child,
  ) {
    final glass = GlassSurface(
      material: GlassMaterial.messageMenu,
      cornerRadius: surface.cornerRadius,
      child: child,
    );
    return switch (surface) {
      ChatMessageMenuSurface$Card() => glass,
      ChatMessageMenuSurface$Reactions() => MessageMenuStripEnter(child: glass),
    };
  }

  /// The desktop card around [child]: the pointer menu's background and
  /// corners ([PointerMenuMetrics.cornerRadius], whatever [surface] says), and the padding above and below the rows of a menu with icons
  /// ([MessageMenuPointerRow.menuPadding]). Its shadow is drawn by the
  /// appear motion under its frame ([desktopShadowsOf]).
  static Widget desktopSurface(
    BuildContext context,
    ChatMessageMenuSurface surface,
    Widget child,
  ) {
    final tokens = ChromeThemeScope.pointerMenuOf(context);
    return ClipRRect(
      borderRadius: const BorderRadius.all(PointerMenuMetrics.cornerRadius),
      child: ColoredBox(
        color: tokens.background,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            vertical: MessageMenuPointerRow.menuPadding,
          ),
          child: child,
        ),
      ),
    );
  }

  /// The pointer menu's shadow in [tokens]: its colour at
  /// [PointerMenuMetrics.shadowOpacity], blurred by
  /// [PointerMenuMetrics.shadowBlur] (a sigma of half of it), moved by
  /// [PointerMenuMetrics.shadowOffset].
  static List<BoxShadow> desktopShadowsOf(PointerMenuTokens tokens) => [
    BoxShadow(
      color: tokens.shadow.withValues(
        alpha: tokens.shadow.a * PointerMenuMetrics.shadowOpacity,
      ),
      // A blur radius r is a sigma of 0.57735 r + 0.5.
      blurRadius: (PointerMenuMetrics.shadowBlur / 2 - 0.5) / 0.57735,
      offset: PointerMenuMetrics.shadowOffset,
    ),
  ];

  /// The menu's enter and leave.
  static Widget transition(
    BuildContext context,
    ChatMessageMenuTransition transition,
    Widget menu,
  ) {
    final android = isAndroidSheet(transition.presentation);
    final desktop = isDesktopPopup(transition.presentation);
    final tokens = desktop ? ChromeThemeScope.pointerMenuOf(context) : null;
    return ChromeAppear(
      visible: transition.visible,
      onHidden: transition.onHidden,
      motion: switch (transition.presentation) {
        ChatMessageMenuPresentation.popup => const AppearMotion.grow(),
        _ when android => const AppearMotion.pop(),
        ChatMessageMenuPresentation.sheet => null,
      },
      origin: android ? Alignment.bottomRight : transition.origin,
      rows: transition.rows,
      borderRadius: desktop
          ? const BorderRadius.all(PointerMenuMetrics.cornerRadius)
          : BorderRadius.zero,
      revealColor: tokens?.background,
      shadows: switch (tokens) {
        final tokens? => desktopShadowsOf(tokens),
        null => const <BoxShadow>[],
      },
      child: menu,
    );
  }
}

/// One action row of the Android message menu: 48 tall, its icon (24) at the
/// start 18 in, its label 43 after the icon's start in the regular face at
/// 16, one line; label and icon in the palette's text colour, a destructive
/// row too; a disabled row is drawn at half opacity. The press feedback is
/// the platform's ([ChromeInk]).
class MessageMenuRow extends StatelessWidget {
  /// A row for [item], chosen by [onTap] (null when the item is disabled).
  const MessageMenuRow({required this.item, required this.onTap, super.key});

  /// The row's height.
  static const double height = 48;

  /// The inset at each side.
  static const double inset = 18;

  /// From the icon's start to the label's.
  static const double labelInset = 43;

  /// The icon's size.
  static const double iconSize = 24;

  /// The label's size.
  static const double fontSize = 16;

  /// The opacity of a disabled row.
  static const double disabledOpacity = 0.5;

  /// The action.
  final ChatMessageMenuAction item;

  /// Chooses the action.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = ChromeThemeScope.paletteOf(context);
    final label = palette.onSurface;
    final icon = palette.onSurface;
    return Semantics(
      button: true,
      enabled: item.enabled,
      label: item.label,
      excludeSemantics: true,
      child: Opacity(
        opacity: item.enabled ? 1 : disabledOpacity,
        child: ChromeInk(
          color: palette.onSurface.withAlpha(0x0F),
          onTap: item.enabled ? onTap : null,
          child: SizedBox(
            height: height,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: inset),
              child: Row(
                children: [
                  SizedBox(
                    width: labelInset,
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Icon(item.icon, size: iconSize, color: icon),
                    ),
                  ),
                  Flexible(
                    child: Text(
                      item.label,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: ChromeTypography.of(
                        context,
                      ).copyWith(fontSize: fontSize, color: label),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One action row of the desktop message menu: the pointer menu's row with
/// an icon.
///
/// Its label is set in the pointer menu's face at
/// [PointerMenuMetrics.fontSize], [labelPadding] around it, so the row is
/// the font's line height and 16 more; the icon ([iconSize]) sits at
/// [iconOffset] from the row's top start. Text and fill are the pointer
/// menu's ([PointerMenuTokens]): its text at rest, its over text on the over
/// fill under the mouse, its disabled text; the icon in [PointerMenuTokens.
/// arrow], the menu's bold colour. A destructive row takes the palette's
/// destructive colour for both. The press is the pointer ripple
/// ([ChromeInk], in [PointerMenuTokens.ripple]).
class MessageMenuPointerRow extends StatefulWidget {
  /// A row for [item], chosen by [onTap] (null when the item is disabled).
  const MessageMenuPointerRow({
    required this.item,
    required this.onTap,
    super.key,
  });

  /// The padding around the label.
  static const EdgeInsetsDirectional labelPadding =
      EdgeInsetsDirectional.fromSTEB(54, 8, 17, 8);

  /// Where the icon's top start corner is in the row.
  static const Offset iconOffset = Offset(15, 5);

  /// The icon's size.
  static const double iconSize = 24;

  /// The padding above the first row and below the last of a menu with
  /// icons.
  static const double menuPadding = 5;

  /// The action.
  final ChatMessageMenuAction item;

  /// Chooses the action.
  final VoidCallback? onTap;

  @override
  State<MessageMenuPointerRow> createState() => _MessageMenuPointerRowState();
}

class _MessageMenuPointerRowState extends State<MessageMenuPointerRow> {
  var _over = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final tokens = ChromeThemeScope.pointerMenuOf(context);
    final palette = ChromeThemeScope.paletteOf(context);
    final enabled = item.enabled;
    final over = enabled && _over;
    final label = switch ((enabled, item.isDestructive)) {
      (false, _) => tokens.textDisabled,
      (true, true) => palette.destructive,
      (true, false) => over ? tokens.textOver : tokens.text,
    };
    final icon = item.isDestructive ? palette.destructive : tokens.arrow;
    return Semantics(
      button: true,
      enabled: enabled,
      label: item.label,
      excludeSemantics: true,
      child: MouseRegion(
        onEnter: (_) => setState(() => _over = true),
        onExit: (_) => setState(() => _over = false),
        child: ChromeInk(
          kind: ChromeInkKind.pointer,
          color: tokens.ripple,
          hoverColor: tokens.backgroundOver,
          onTap: enabled ? widget.onTap : null,
          child: Stack(
            children: [
              PositionedDirectional(
                start: MessageMenuPointerRow.iconOffset.dx,
                top: MessageMenuPointerRow.iconOffset.dy,
                child: Icon(
                  item.icon,
                  size: MessageMenuPointerRow.iconSize,
                  color: enabled ? icon : tokens.textDisabled,
                ),
              ),
              Padding(
                padding: MessageMenuPointerRow.labelPadding,
                child: Text(
                  item.label,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: ChromeTypography.of(context).copyWith(
                    fontSize: PointerMenuMetrics.fontSize,
                    color: label,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// How the Android message menu's reaction strip comes in, on its own while
/// the menu pops: over 250 ms on an overshoot (tension 0.5), it scales up
/// from nothing about a point an eighth of its width from its end, at mid
/// height, while its shape opens from its end: its start edge comes from
/// three quarters of the way across (a quarter of it shows from the first
/// frame).
class MessageMenuStripEnter extends StatefulWidget {
  /// Brings [child], the strip, in.
  const MessageMenuStripEnter({required this.child, super.key});

  /// How long the entry takes.
  static const Duration duration = Duration(milliseconds: 250);

  /// Its curve.
  static const Curve curve = OvershootCurve(0.5);

  /// The share of the strip that shows from the first frame.
  static const double startShown = 0.25;

  /// The strip.
  final Widget child;

  @override
  State<MessageMenuStripEnter> createState() => _MessageMenuStripEnterState();
}

class _MessageMenuStripEnterState extends State<MessageMenuStripEnter>
    with SingleTickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(vsync: this);
  var _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final speed =
        (ChromeMotionScope.maybeOf(context) ?? ChromeMotionData.standard).speed;
    _clock
      ..duration = speed.scale(MessageMenuStripEnter.duration)
      ..forward().ignore();
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _clock,
    builder: (context, child) {
      if (_clock.isCompleted) return child!;
      final p = MessageMenuStripEnter.curve.transform(_clock.value);
      final rtl = Directionality.maybeOf(context) == TextDirection.rtl;
      return Transform.scale(
        scale: p,
        // An eighth of the width from the end, at mid height.
        alignment: Alignment(rtl ? -0.75 : 0.75, 0),
        child: ClipRect(
          clipper: _StripClip(
            shown: math.max(MessageMenuStripEnter.startShown, p),
            rtl: rtl,
          ),
          child: child,
        ),
      );
    },
    child: widget.child,
  );
}

class _StripClip extends CustomClipper<Rect> {
  const _StripClip({required this.shown, required this.rtl});

  final double shown;
  final bool rtl;

  @override
  Rect getClip(Size size) {
    final width = size.width * shown.clamp(0.0, 1.0);
    return rtl
        ? Rect.fromLTWH(0, 0, width, size.height)
        : Rect.fromLTWH(size.width - width, 0, width, size.height);
  }

  @override
  bool shouldReclip(_StripClip oldClipper) =>
      oldClipper.shown != shown || oldClipper.rtl != rtl;
}

/// The band between the Android message menu's rows and an entry below them
/// in the same card: 8 tall across the card, the text colour at 6% over the
/// glass, with the platform's grey divider shadow (black at 8%, 4% and 1%
/// down its top three, 1% on its bottom one).
class MessageMenuGapBand extends StatelessWidget {
  /// A band.
  const MessageMenuGapBand({super.key});

  /// Its height.
  static const double height = 8;

  /// The opacity of the text colour it is filled with.
  static const double fillOpacity = 0.06;

  @override
  Widget build(BuildContext context) {
    final palette = ChromeThemeScope.paletteOf(context);
    return SizedBox(
      height: height,
      child: CustomPaint(
        painter: _GapBandPainter(
          fill: palette.onSurface.withValues(alpha: fillOpacity),
          shadow: palette.shadow,
        ),
      ),
    );
  }
}

class _GapBandPainter extends CustomPainter {
  const _GapBandPainter({required this.fill, required this.shadow});

  final Color fill;
  final Color shadow;

  // The divider's alpha, of 255, on its top lines and its bottom one.
  static const List<int> _top = [20, 10, 3];
  static const int _bottom = 3;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = fill);
    for (var i = 0; i < _top.length; i++) {
      canvas.drawRect(
        Rect.fromLTWH(0, i.toDouble(), size.width, 1),
        Paint()..color = shadow.withAlpha(_top[i]),
      );
    }
    canvas.drawRect(
      Rect.fromLTWH(0, size.height - 1, size.width, 1),
      Paint()..color = shadow.withAlpha(_bottom),
    );
  }

  @override
  bool shouldRepaint(_GapBandPainter oldDelegate) =>
      oldDelegate.fill != fill || oldDelegate.shadow != shadow;
}
