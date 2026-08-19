import 'package:chat_scroll_view/src/chat_widgets/message_menu/chat_message_menu_item.dart';
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
    final colorScheme = Theme.of(context).colorScheme;
    const radius = BorderRadius.all(Radius.circular(12));

    return Align(
      alignment: Alignment.topLeft,
      widthFactor: 1,
      heightFactor: 1,
      child: SizedBox(
        width: minWidth.clamp(0, maxWidth),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            borderRadius: radius,
            boxShadow: <BoxShadow>[
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
            color: Color.alphaBlend(
              colorScheme.onSurface.withValues(alpha: 0.08),
              colorScheme.surface,
            ),
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
    super.key,
  });

  /// Rows to show.
  final List<ChatMessageMenuItem> items;

  /// Called with the item id when tapped.
  final ValueChanged<String> onSelect;

  static const double _tileHeight = 48;
  static const double _tilePadding = 18;
  static const double _iconSize = 24;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final onSurface = colorScheme.onSurface;
    final error = colorScheme.error;

    return ChatMessageMenuCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (var i = 0; i < items.length; i++) ...<Widget>[
            if (i > 0 && _shouldGapBefore(items, i))
              Divider(
                height: 1,
                thickness: 1,
                color: colorScheme.outlineVariant.withValues(alpha: 0.45),
              ),
            _ActionRow(
              item: items[i],
              onSurface: onSurface,
              error: error,
              onTap: items[i].enabled ? () => onSelect(items[i].id) : null,
            ),
          ],
        ],
      ),
    );
  }

  static bool _shouldGapBefore(List<ChatMessageMenuItem> items, int index) {
    if (index <= 0) return false;
    final prev = items[index - 1];
    final cur = items[index];
    return cur.isDestructive && !prev.isDestructive;
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.item,
    required this.onSurface,
    required this.error,
    required this.onTap,
  });

  final ChatMessageMenuItem item;
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

    return Material(
      color: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: ChatMessageMenuActionList._tileHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: ChatMessageMenuActionList._tilePadding,
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  item.icon,
                  size: ChatMessageMenuActionList._iconSize,
                  color: color,
                ),
                const SizedBox(width: 19),
                Expanded(
                  child: Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontSize: 16,
                      color: color,
                    ),
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
