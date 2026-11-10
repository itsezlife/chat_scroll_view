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
/// its top right corner (it hangs left of the press). Elsewhere the rows and
/// the card are the package's, a popup grows from the pointer and a sheet
/// plays the platform's appear motion.
abstract final class MessageMenuChrome {
  /// Whether a menu of [presentation] takes the Android chrome on this
  /// platform.
  static bool isAndroidSheet(ChatMessageMenuPresentation presentation) =>
      presentation == ChatMessageMenuPresentation.sheet &&
      ChromeInkKind.forPlatform(defaultTargetPlatform) == ChromeInkKind.ripple;

  /// The rows of a menu of [presentation], or null for the package's.
  static ChatMessageMenuItemBuilder? itemBuilderFor(
    ChatMessageMenuPresentation presentation,
  ) => isAndroidSheet(presentation)
      ? (context, item, onSelect) => MessageMenuRow(item: item, onTap: onSelect)
      : null;

  /// The action card's surface for [presentation], or null for the
  /// package's.
  static ChatMessageMenuSurfaceBuilder? surfaceBuilderFor(
    ChatMessageMenuPresentation presentation,
  ) => isAndroidSheet(presentation) ? surface : null;

  /// The scrim menu glass around [rows], whose content blooms with the
  /// menu.
  static Widget surface(BuildContext context, Widget rows) => GlassSurface(
    material: GlassMaterial.scrimMenu,
    child: AppearContent(child: rows),
  );

  /// The menu's enter and leave.
  static Widget transition(
    BuildContext context,
    ChatMessageMenuTransition transition,
    Widget menu,
  ) {
    final android = isAndroidSheet(transition.presentation);
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
      child: menu,
    );
  }
}

/// One action row of the Android message menu: 48 tall, its icon (24) at the
/// start 18 in, its label 43 after the icon's start in the regular face at
/// 16, one line; a disabled row is drawn at half opacity. The press feedback
/// is the platform's ([ChromeInk]).
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
    final label = item.isDestructive ? palette.destructive : palette.onSurface;
    final icon = item.isDestructive ? palette.destructive : palette.iconIdle;
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
