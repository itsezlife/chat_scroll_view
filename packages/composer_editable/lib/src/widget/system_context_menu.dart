import 'package:composer_editable/src/widget/editable_text.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// The iOS system context menu for an [ExtendedEditableTextState].
///
/// Stock [SystemContextMenu.editableText] takes a stock [EditableTextState],
/// which [ExtendedEditableTextState] is not, and its constructor with an
/// explicit anchor is private. This widget is the same thing over the public
/// pieces ([SystemContextMenuController], [IOSSystemContextMenuItem],
/// [TextSelectionToolbarAnchors.getSelectionRect]), so the platform menu stays
/// reachable on the extended editable's menu-builder path.
///
/// Like the stock widget it draws nothing itself: building it asks the
/// platform to show its menu, and it only exists where
/// [isSupportedByField] holds.
class ExtendedSystemContextMenu extends StatefulWidget {
  const ExtendedSystemContextMenu._({
    required this.anchor,
    required this.items,
    super.key,
    this.onSystemHide,
  });

  /// Creates the menu for the field [editableTextState] belongs to.
  ///
  /// [items] defaults to [getDefaultItems].
  factory ExtendedSystemContextMenu.editableText({
    required ExtendedEditableTextState editableTextState,
    Key? key,
    List<IOSSystemContextMenuItem>? items,
  }) {
    final (:startGlyphHeight, :endGlyphHeight) = editableTextState
        .getGlyphHeights();
    final renderEditable = editableTextState.renderEditable;
    return ExtendedSystemContextMenu._(
      key: key,
      anchor: TextSelectionToolbarAnchors.getSelectionRect(
        renderEditable,
        startGlyphHeight,
        endGlyphHeight,
        renderEditable.getEndpointsForSelection(
          editableTextState.textEditingValue.selection,
        ),
      ),
      items: items ?? getDefaultItems(editableTextState),
      onSystemHide: () => editableTextState.hideToolbar(false),
    );
  }

  /// The rectangle the menu points to.
  final Rect anchor;

  /// The buttons the platform shows.
  final List<IOSSystemContextMenuItem> items;

  /// Called when the platform hides the menu on its own, for example on a tap
  /// outside it.
  final VoidCallback? onSystemHide;

  /// Whether the field can show the system menu.
  ///
  /// The platform menu needs an active input connection, so a read-only field
  /// falls back to the Flutter-drawn toolbar.
  static bool isSupportedByField(ExtendedEditableTextState editableTextState) =>
      !editableTextState.widget.readOnly &&
      SystemContextMenu.isSupported(editableTextState.context);

  /// The buttons that fit the field's current state, from the same list the
  /// Flutter-drawn toolbar uses ([ExtendedEditableTextState.contextMenuButtonItems]),
  /// so the two menus cannot disagree about Copy or Paste.
  static List<IOSSystemContextMenuItem> getDefaultItems(
    ExtendedEditableTextState editableTextState,
  ) => <IOSSystemContextMenuItem>[
    for (final ContextMenuButtonItem button
        in editableTextState.contextMenuButtonItems)
      ?switch (button.type) {
        ContextMenuButtonType.copy => const IOSSystemContextMenuItemCopy(),
        ContextMenuButtonType.cut => const IOSSystemContextMenuItemCut(),
        ContextMenuButtonType.paste => const IOSSystemContextMenuItemPaste(),
        ContextMenuButtonType.selectAll =>
          const IOSSystemContextMenuItemSelectAll(),
        ContextMenuButtonType.lookUp => const IOSSystemContextMenuItemLookUp(),
        ContextMenuButtonType.searchWeb =>
          const IOSSystemContextMenuItemSearchWeb(),
        ContextMenuButtonType.share => const IOSSystemContextMenuItemShare(),
        ContextMenuButtonType.liveTextInput =>
          const IOSSystemContextMenuItemLiveText(),
        // The platform has no Delete button, and custom items are passed in
        // through [items], not derived.
        ContextMenuButtonType.delete || ContextMenuButtonType.custom => null,
      },
  ];

  @override
  State<ExtendedSystemContextMenu> createState() =>
      _ExtendedSystemContextMenuState();
}

class _ExtendedSystemContextMenuState extends State<ExtendedSystemContextMenu> {
  late final SystemContextMenuController _controller;

  @override
  void initState() {
    super.initState();
    _controller = SystemContextMenuController(
      onSystemHide: widget.onSystemHide,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    assert(
      SystemContextMenu.isSupported(context),
      'The system context menu is only built where the platform supports it; '
      'check ExtendedSystemContextMenu.isSupportedByField first.',
    );
    if (widget.items.isNotEmpty) {
      final localizations = WidgetsLocalizations.of(context);
      _controller.showWithItems(widget.anchor, <IOSSystemContextMenuItemData>[
        for (final IOSSystemContextMenuItem item in widget.items)
          item.getData(localizations),
      ]);
    }
    return const SizedBox.shrink();
  }
}
