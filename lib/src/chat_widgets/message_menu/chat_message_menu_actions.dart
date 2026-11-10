import 'dart:math' as math;

import 'package:chat_scroll_view/src/chat_widgets/chat_scroll_theme.dart';
import 'package:chat_scroll_view/src/chat_widgets/message_menu/chat_message_menu_item.dart';
import 'package:chat_scroll_view/src/chat_widgets/message_menu/chat_message_menu_slots.dart';
import 'package:flutter/material.dart';

/// Card without M3 elevation overlays.
///
/// The card takes the width of its widest row ([child]'s intrinsic width),
/// no narrower than [minWidth] and no wider than [maxWidth] or the room it
/// is given; a row wider than that ellipsizes. Every row reports its
/// intrinsic width (a `LayoutBuilder` or a scrollable row cannot).
///
/// [surfaceBuilder], when given, draws the card's surface in place of the
/// package fill, corners and shadow (a host's glass): it gets the rows and
/// clips them to its own shape.
class ChatMessageMenuCard extends StatelessWidget {
  /// Creates a menu card.
  const ChatMessageMenuCard({
    required this.child,
    this.maxWidth = double.infinity,
    this.minWidth = defaultMinWidth,
    this.surfaceBuilder,
    super.key,
  });

  /// Minimum width for the action card (logical px).
  static const double defaultMinWidth = 200;

  /// Minimum width of a popup's card: the desktop pointer menu's.
  static const double popupMinWidth = 156;

  /// Maximum width of a popup's card: the desktop pointer menu's.
  static const double popupMaxWidth = 300;

  /// Maximum width of the reactions strip.
  static const double defaultMaxWidth = 280;

  /// Menu body.
  final Widget child;

  /// Max card width.
  final double maxWidth;

  /// Minimum card width.
  final double minWidth;

  /// The host's surface around the rows, or null for the package card.
  final ChatMessageMenuSurfaceBuilder? surfaceBuilder;

  @override
  Widget build(BuildContext context) {
    // The rows fill the card whatever constraints the surface hands them (a
    // stack lays its child out loosely), so their ink spans it; the card's
    // width is measured around the surface.
    final rows = SizedBox(width: double.infinity, child: child);
    final surface = switch (surfaceBuilder) {
      final builder? => builder(
        context,
        ChatScrollTheme.menuOf(context).cardRadius ?? 12,
        // The rows' ink layer: a host surface is not a Material.
        Material(type: MaterialType.transparency, child: rows),
      ),
      null => _PackageSurface(child: rows),
    };
    return Align(
      alignment: AlignmentDirectional.topStart,
      widthFactor: 1,
      heightFactor: 1,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: minWidth,
          maxWidth: math.max(minWidth, maxWidth),
        ),
        child: IntrinsicWidth(child: surface),
      ),
    );
  }
}

class _PackageSurface extends StatelessWidget {
  const _PackageSurface({required this.child});

  final Widget child;

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

    return DecoratedBox(
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
    this.surfaceBuilder,
    this.minWidth = ChatMessageMenuCard.defaultMinWidth,
    this.maxWidth = double.infinity,
    super.key,
  });

  /// The narrowest the card is.
  final double minWidth;

  /// The widest the card is.
  final double maxWidth;

  /// Rows to show.
  final List<ChatMessageMenuItem> items;

  /// Called with the item id when tapped.
  final ValueChanged<String> onSelect;

  /// Optional custom row. Null uses the package row.
  final ChatMessageMenuItemBuilder? itemBuilder;

  /// Optional surface around the rows. Null uses the package card.
  final ChatMessageMenuSurfaceBuilder? surfaceBuilder;

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
      surfaceBuilder: surfaceBuilder,
      minWidth: minWidth,
      maxWidth: maxWidth,
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
