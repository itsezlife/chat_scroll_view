import 'package:chat_scroll_view/src/chat_widgets/chat_scroll_theme.dart';
import 'package:chat_scroll_view/src/chat_widgets/message_menu/chat_message_menu_item.dart';
import 'package:chat_scroll_view/src/chat_widgets/message_menu/chat_message_menu_slots.dart';
import 'package:flutter/material.dart';

/// Minimum width for the action card.
///
/// Telegram `ActionBarPopupWindowLayout.setMinimumWidth(dp(200))`.
const double kChatMessageMenuMinWidth = 200;

/// Maximum width for the action card and reactions strip.
///
/// Telegram sizes the popup `WRAP_CONTENT` to the action rows; reactions
/// are `MATCH_PARENT` to that width. Capping here keeps the column from
/// expanding to the screen and pinning to the left inset.
const double kChatMessageMenuMaxWidth = 280;

/// Card without M3 elevation overlays.
class ChatMessageMenuCard extends StatelessWidget {
  /// Creates a menu card.
  const ChatMessageMenuCard({
    required this.child,
    this.maxWidth = kChatMessageMenuMaxWidth,
    this.minWidth = kChatMessageMenuMinWidth,
    super.key,
  });

  /// Menu body.
  final Widget child;

  /// Max bubble width.
  final double maxWidth;

  /// Minimum bubble width.
  final double minWidth;

  @override
  Widget build(BuildContext context) {
    final menuTheme = ChatScrollTheme.menuOf(context);
    final colorScheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.all(
      Radius.circular(menuTheme.cardRadius ?? 12),
    );
    final fill =
        menuTheme.cardColor ??
        Color.alphaBlend(
          colorScheme.onSurface.withValues(alpha: 0.08),
          colorScheme.surface,
        );

    return Align(
      alignment: Alignment.topLeft,
      widthFactor: 1,
      heightFactor: 1,
      child: SizedBox(
        width: minWidth.clamp(0, maxWidth),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            boxShadow:
                menuTheme.cardShadow ??
                const <BoxShadow>[
                  BoxShadow(
                    color: Color.fromRGBO(0, 0, 0, 0.35),
                    blurRadius: 12,
                    offset: Offset(0, 4),
                  ),
                ],
          ),
          child: Material(
            elevation: 0,
            shadowColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            borderRadius: radius,
            clipBehavior: Clip.antiAlias,
            color: fill,
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Vertical action list.
class ChatMessageMenuActionList extends StatelessWidget {
  /// Creates an action list card.
  const ChatMessageMenuActionList({
    required this.items,
    required this.onSelect,
    this.itemBuilder,
    super.key,
  });

  /// Rows to show.
  final List<ChatMessageMenuItem> items;

  /// Called with the item id when tapped.
  final ValueChanged<String> onSelect;

  /// Optional custom row. Null uses the package row.
  final ChatMessageMenuItemBuilder? itemBuilder;

  static const double _tileHeight = 48;
  static const double _tilePadding = 18;
  static const double _iconSize = 24;

  @override
  Widget build(BuildContext context) {
    final menuTheme = ChatScrollTheme.menuOf(context);
    final colorScheme = Theme.of(context).colorScheme;
    final onSurface = colorScheme.onSurface;
    final error = menuTheme.destructiveColor ?? colorScheme.error;

    return ChatMessageMenuCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final item in items)
            switch (item) {
              ChatMessageMenuDivider() => Divider(
                height: 1,
                thickness: 1,
                color:
                    menuTheme.dividerColor ??
                    colorScheme.outlineVariant.withValues(alpha: 0.45),
              ),
              ChatMessageMenuCustom(:final builder) => builder(context),
              ChatMessageMenuAction() =>
                itemBuilder?.call(
                      context,
                      item,
                      item.enabled ? () => onSelect(item.id) : null,
                    ) ??
                    _ActionRow(
                      item: item,
                      onSurface: onSurface,
                      error: error,
                      onTap: item.enabled ? () => onSelect(item.id) : null,
                    ),
            },
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.item,
    required this.onSurface,
    required this.error,
    required this.onTap,
  });

  final ChatMessageMenuAction item;
  final Color onSurface;
  final Color error;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = !item.enabled
        ? onSurface.withValues(alpha: 0.38)
        : item.isDestructive
        ? error
        : onSurface;

    final menuTheme = ChatScrollTheme.menuOf(context);
    return Material(
      color: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height:
              menuTheme.actionTileHeight ??
              ChatMessageMenuActionList._tileHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: ChatMessageMenuActionList._tilePadding,
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  item.icon,
                  size:
                      menuTheme.actionIconSize ??
                      ChatMessageMenuActionList._iconSize,
                  color: color,
                ),
                const SizedBox(width: 19),
                Expanded(
                  child: Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        (menuTheme.actionLabelStyle ??
                                theme.textTheme.labelLarge?.copyWith(
                                  fontSize: 16,
                                ))
                            ?.copyWith(color: color),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
