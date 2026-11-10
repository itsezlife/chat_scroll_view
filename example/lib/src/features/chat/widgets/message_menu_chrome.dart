import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// How the message menu looks and moves in the app's chrome, per platform
/// family: the builders the host hands `ChatMessageMenu.show`.
///
/// On Android a sheet menu takes the chrome's own rows ([MessageMenuRow])
/// on the scrim menu glass ([GlassMaterial.scrimMenu]), and comes up by the
/// bloom when it has a reaction strip and by the pop when it has none, from
/// its top right corner (it hangs left of the press). On a desktop a popup
/// takes the same rows, in the pointer menu's colours, on a solid card of the
/// pointer menu's shape ([desktopSurface]), and grows from the corner at the
/// pointer. Elsewhere the rows and the card are the package's and a sheet
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
          MessageMenuRow.pointer(context, item: item, onTap: onSelect),
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

  /// The scrim menu glass, of [cornerRadius], around [child] (the action
  /// card's rows or the reaction strip), whose content blooms with the menu.
  static Widget surface(
    BuildContext context,
    double cornerRadius,
    Widget child,
  ) => GlassSurface(
    material: GlassMaterial.scrimMenu,
    cornerRadius: cornerRadius,
    child: AppearContent(child: child),
  );

  /// The desktop card around [child]: the pointer menu's background,
  /// corners ([PointerMenuMetrics.cornerRadius], whatever [cornerRadius]
  /// says) and padding above and below the rows
  /// ([PointerMenuMetrics.verticalPadding]). Its shadow is drawn by the
  /// appear motion under its frame ([desktopShadowsOf]).
  static Widget desktopSurface(
    BuildContext context,
    double cornerRadius,
    Widget child,
  ) {
    final tokens = ChromeThemeScope.pointerMenuOf(context);
    return ClipRRect(
      borderRadius: const BorderRadius.all(PointerMenuMetrics.cornerRadius),
      child: ColoredBox(
        color: tokens.background,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            vertical: PointerMenuMetrics.verticalPadding,
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
        _ when android && transition.hasReactions => const AppearMotion.bloom(),
        _ when android => const AppearMotion.pop(),
        ChatMessageMenuPresentation.sheet => null,
      },
      origin: android ? Alignment.topRight : transition.origin,
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

/// One action row of the message menu: 48 tall, its icon (24) at the start
/// 18 in, its label 43 after the icon's start in the regular face at 16, one
/// line; a disabled row is drawn at half opacity. The press feedback is the
/// platform's ([ChromeInk]).
///
/// Its colours are the palette's (the Android menu's) unless given: the
/// desktop menu ([MessageMenuRow.pointer]) takes the pointer menu's.
class MessageMenuRow extends StatelessWidget {
  /// A row for [item], chosen by [onTap] (null when the item is disabled).
  const MessageMenuRow({
    required this.item,
    required this.onTap,
    this.labelColor,
    this.iconColor,
    this.inkColor,
    this.hoverColor,
    super.key,
  });

  /// A row in the pointer menu's colours of [context]: its text, its hint
  /// colour for the icon, its ripple and its hover fill.
  factory MessageMenuRow.pointer(
    BuildContext context, {
    required ChatMessageMenuAction item,
    required VoidCallback? onTap,
  }) {
    final tokens = ChromeThemeScope.pointerMenuOf(context);
    return MessageMenuRow(
      item: item,
      onTap: onTap,
      labelColor: tokens.text,
      iconColor: tokens.hint,
      inkColor: tokens.ripple,
      hoverColor: tokens.backgroundOver,
    );
  }

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

  /// The label's colour, or null for the palette's.
  final Color? labelColor;

  /// The icon's colour, or null for the palette's.
  final Color? iconColor;

  /// The press feedback's colour, or null for the palette's.
  final Color? inkColor;

  /// The fill under a hovering mouse, or null for none.
  final Color? hoverColor;

  @override
  Widget build(BuildContext context) {
    final palette = ChromeThemeScope.paletteOf(context);
    final label = item.isDestructive
        ? palette.destructive
        : labelColor ?? palette.onSurface;
    final icon = item.isDestructive
        ? palette.destructive
        : iconColor ?? palette.iconIdle;
    return Semantics(
      button: true,
      enabled: item.enabled,
      label: item.label,
      excludeSemantics: true,
      child: Opacity(
        opacity: item.enabled ? 1 : disabledOpacity,
        child: ChromeInk(
          color: inkColor ?? palette.onSurface.withAlpha(0x0F),
          hoverColor: hoverColor,
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
