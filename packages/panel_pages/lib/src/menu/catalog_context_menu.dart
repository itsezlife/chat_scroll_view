import 'dart:math' as math;

import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:panel_pages/src/policy/catalog_page_policy.dart';
import 'package:panel_pages/src/theme/chrome_catalog_theme.dart';
import 'package:panel_shell/panel_shell.dart';

/// Opens the context menu of a [CatalogContextMenuHost], from outside its
/// subtree.
///
/// The page that owns the host owns the controller too; nothing else needs it.
final class CatalogContextMenuController {
  _CatalogContextMenuHostState? _state;

  /// Whether a menu is up.
  bool get isOpen => _state?._isOpen ?? false;

  /// Opens a menu of [entries] with its corner at [globalPosition], or moves
  /// the one that is up. [onSelected] hears the id of the item the user
  /// chooses, after the menu has closed.
  ///
  /// Does nothing for [entries] with no item, and while no host is mounted.
  void show({
    required Offset globalPosition,
    required List<CatalogMenuEntry> entries,
    required ValueChanged<String> onSelected,
  }) => _state?._show(globalPosition, entries, onSelected);

  /// Closes the menu. Does nothing when none is up.
  void close() => _state?._close();

  /// Forgets the host; after it [show] and [close] do nothing.
  void dispose() => _state = null;
}

/// Gives its subtree a context menu, built on the framework's
/// [RawMenuAnchor]: the anchor owns the overlay of the menu and its open and
/// close, and the panel here draws what is in it.
///
/// - **Where.** At a position the page names, in the nearest `Overlay`. The
///   menu is built as part of this subtree (an `OverlayPortal`), so it sees
///   the same chrome theme, strings and reading direction as the page.
/// - **Modal, like a native menu.** A press anywhere else closes it and goes
///   no further: the click that dismisses a menu does not also pick the cell
///   under it. Escape closes it; the arrows move between items and Enter
///   chooses.
/// - **Focus.** The menu takes focus while it is up, for its keys, and gives
///   it back to what had it (the composer's field) when it closes.
/// - **Hold.** The menu sits outside the panel's own box, so the pointer
///   moving onto it reads as leaving the panel; the hold on auto-hide
///   ([PanelPageHost.holdAutoHide]) is taken as it opens and released as it
///   closes, or with the page.
class CatalogContextMenuHost extends StatefulWidget {
  /// A host that holds auto-hide through [host] while its menu is up.
  const CatalogContextMenuHost({
    required this.host,
    required this.controller,
    required this.child,
    super.key,
  });

  /// The page's connection to the shell.
  final PanelPageHost host;

  /// The handle the page opens the menu with.
  final CatalogContextMenuController controller;

  /// The subtree the menu belongs to.
  final Widget child;

  @override
  State<CatalogContextMenuHost> createState() => _CatalogContextMenuHostState();
}

class _CatalogContextMenuHostState extends State<CatalogContextMenuHost> {
  final _menu = MenuController();
  var _entries = const <CatalogMenuEntry>[];
  ValueChanged<String>? _onSelected;
  PanelPageHold? _hold;
  Offset _at = Offset.zero;
  var _moving = false;

  bool get _isOpen => _hold != null;

  @override
  void initState() {
    super.initState();
    widget.controller._state = this;
  }

  @override
  void didUpdateWidget(CatalogContextMenuHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller._state = null;
      widget.controller._state = this;
    }
  }

  @override
  void dispose() {
    if (identical(widget.controller._state, this)) {
      widget.controller._state = null;
    }
    _releaseHold();
    super.dispose();
  }

  void _show(
    Offset globalPosition,
    List<CatalogMenuEntry> entries,
    ValueChanged<String> onSelected,
  ) {
    if (!entries.any((entry) => entry is CatalogMenuItem)) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    _entries = entries;
    _onSelected = onSelected;
    // The hold goes up before the menu does: the move onto it is the first
    // thing the panel's hover rule hears of.
    _hold ??= widget.host.holdAutoHide();
    _at = box.globalToLocal(globalPosition);
    // The anchor closes an open menu before it opens it elsewhere; that close
    // is a move, and the hold goes on through it.
    _moving = true;
    _menu.open(position: _at);
    _moving = false;
  }

  void _close() {
    if (!_isOpen) return;
    _menu.close();
    _releaseHold();
  }

  void _releaseHold() {
    _hold?.release();
    _hold = null;
  }

  void _choose(String id) {
    final onSelected = _onSelected;
    _close();
    onSelected?.call(id);
  }

  @override
  Widget build(BuildContext context) => RawMenuAnchor(
    controller: _menu,
    // The menu closes through [_close], which also lets go of the hold; the
    // anchor's own closing (a dismiss intent, a dispose) arrives here.
    onClose: () {
      if (!_moving) _releaseHold();
    },
    overlayBuilder: (context, info) => _MenuSurface(
      position: info.anchorRect.topLeft + (info.position ?? Offset.zero),
      overlaySize: info.overlaySize,
      entries: _entries,
      onChoose: _choose,
      onDismiss: _close,
    ),
    child: widget.child,
  );
}

// The modal surface: a barrier that swallows the press that dismisses, and
// the panel placed against the window.
class _MenuSurface extends StatelessWidget {
  const _MenuSurface({
    required this.position,
    required this.overlaySize,
    required this.entries,
    required this.onChoose,
    required this.onDismiss,
  });

  final Offset position;
  final Size overlaySize;
  final List<CatalogMenuEntry> entries;
  final ValueChanged<String> onChoose;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      Listener(
        // Opaque: nothing below hears a press while the menu is up, so the
        // click that closes it picks nothing. Any button closes it.
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) => onDismiss(),
      ),
      CustomSingleChildLayout(
        delegate: _MenuLayout(
          position: position,
          textDirection: Directionality.of(context),
        ),
        child: CatalogContextMenuPanel(
          entries: entries,
          onChoose: onChoose,
          onDismiss: onDismiss,
        ),
      ),
    ],
  );
}

// Corner at the pointer, on the side the reading direction opens to and below
// it; back from the pointer on a side that would leave the window.
class _MenuLayout extends SingleChildLayoutDelegate {
  const _MenuLayout({required this.position, required this.textDirection});

  final Offset position;
  final TextDirection textDirection;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final forward = textDirection == TextDirection.ltr;
    var x = forward ? position.dx : position.dx - childSize.width;
    if (x < 0 || x + childSize.width > size.width) {
      x = forward ? position.dx - childSize.width : position.dx;
    }
    var y = position.dy;
    if (y + childSize.height > size.height) y = position.dy - childSize.height;
    return Offset(
      x.clamp(0, math.max(0, size.width - childSize.width)),
      y.clamp(0, math.max(0, size.height - childSize.height)),
    );
  }

  @override
  bool shouldRelayout(_MenuLayout oldDelegate) =>
      oldDelegate.position != position ||
      oldDelegate.textDirection != textDirection;
}

/// The drawn menu: a raised card of items and separators that keeps its own
/// focus scope, handles its keys and gives focus back when it goes.
///
/// Public so a test can find it; a page opens one through a
/// [CatalogContextMenuHost], which places it.
class CatalogContextMenuPanel extends StatefulWidget {
  /// A panel of [entries]; [onChoose] hears an item's id and [onDismiss] an
  /// Escape.
  const CatalogContextMenuPanel({
    required this.entries,
    required this.onChoose,
    required this.onDismiss,
    super.key,
  });

  /// What the menu holds, in order.
  final List<CatalogMenuEntry> entries;

  /// The user chose the item with this id.
  final ValueChanged<String> onChoose;

  /// The user asked to close the menu.
  final VoidCallback onDismiss;

  /// Height of one item.
  static const double itemExtent = 36;

  /// Narrowest a menu is.
  static const double minWidth = 180;

  /// Corner radius of the card.
  static const double radius = 8;

  @override
  State<CatalogContextMenuPanel> createState() =>
      _CatalogContextMenuPanelState();
}

class _CatalogContextMenuPanelState extends State<CatalogContextMenuPanel> {
  final _scope = FocusScopeNode(debugLabel: 'CatalogContextMenu');
  late final FocusNode? _previous = FocusManager.instance.primaryFocus;
  late List<FocusNode> _nodes;

  static const _shortcuts = <ShortcutActivator, Intent>{
    SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
    SingleActivator(LogicalKeyboardKey.arrowDown): NextFocusIntent(),
    SingleActivator(LogicalKeyboardKey.arrowUp): PreviousFocusIntent(),
    SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
    SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
    SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
  };

  @override
  void initState() {
    super.initState();
    _nodes = _nodesFor(widget.entries);
    // The keys go to the menu while it is up. The composer keeps its caret in
    // its own node and has it back at the end.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _nodes.isNotEmpty) _nodes.first.requestFocus();
    });
  }

  @override
  void didUpdateWidget(CatalogContextMenuPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entries != widget.entries) {
      for (final node in _nodes) {
        node.dispose();
      }
      _nodes = _nodesFor(widget.entries);
    }
  }

  @override
  void dispose() {
    final previous = _previous;
    final restore = _scope.hasFocus;
    for (final node in _nodes) {
      node.dispose();
    }
    _scope.dispose();
    if (restore && previous != null) {
      // After this frame: the node that has focus is leaving the tree.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (previous.context != null && previous.canRequestFocus) {
          previous.requestFocus();
        }
      });
    }
    super.dispose();
  }

  List<FocusNode> _nodesFor(List<CatalogMenuEntry> entries) => [
    for (final entry in entries)
      if (entry is CatalogMenuItem) FocusNode(debugLabel: entry.id),
  ];

  @override
  Widget build(BuildContext context) {
    final palette = ChromeThemeScope.paletteOf(context);
    var item = 0;
    return FocusScope(
      node: _scope,
      child: FocusTraversalGroup(
        policy: ReadingOrderTraversalPolicy(),
        child: Shortcuts(
          shortcuts: _shortcuts,
          child: Actions(
            actions: <Type, Action<Intent>>{
              DismissIntent: CallbackAction<DismissIntent>(
                onInvoke: (_) {
                  widget.onDismiss();
                  return null;
                },
              ),
              NextFocusIntent: NextFocusAction(),
              PreviousFocusIntent: PreviousFocusAction(),
            },
            child: Semantics(
              container: true,
              explicitChildNodes: true,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: palette.surfaceRaised,
                  borderRadius: BorderRadius.circular(
                    CatalogContextMenuPanel.radius,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: palette.shadow.withValues(alpha: 0.28),
                      blurRadius: 12,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minWidth: CatalogContextMenuPanel.minWidth,
                  ),
                  child: IntrinsicWidth(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final entry in widget.entries)
                            switch (entry) {
                              final CatalogMenuItem entry => _MenuItemView(
                                item: entry,
                                node: _nodes[item++],
                                palette: palette,
                                onChoose: () => widget.onChoose(entry.id),
                              ),
                              CatalogMenuSeparator() => Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 4,
                                ),
                                child: SizedBox(
                                  height: 1,
                                  child: ColoredBox(color: palette.separator),
                                ),
                              ),
                            },
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MenuItemView extends StatefulWidget {
  const _MenuItemView({
    required this.item,
    required this.node,
    required this.palette,
    required this.onChoose,
  });

  final CatalogMenuItem item;
  final FocusNode node;
  final ChromePalette palette;
  final VoidCallback onChoose;

  @override
  State<_MenuItemView> createState() => _MenuItemViewState();
}

class _MenuItemViewState extends State<_MenuItemView> {
  var _hovered = false;
  var _focused = false;

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final item = widget.item;
    return Semantics(
      button: true,
      label: item.label,
      onTap: widget.onChoose,
      excludeSemantics: true,
      child: FocusableActionDetector(
        focusNode: widget.node,
        mouseCursor: SystemMouseCursors.click,
        onShowHoverHighlight: (value) => setState(() => _hovered = value),
        onShowFocusHighlight: (value) => setState(() => _focused = value),
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onChoose();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onChoose,
          child: Container(
            height: CatalogContextMenuPanel.itemExtent,
            alignment: AlignmentDirectional.centerStart,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            color: _hovered || _focused
                ? ChromeCatalogTheme.hoverWashOf(palette)
                : const Color(0x00000000),
            child: Text(
              item.label,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                height: 1.2,
                decoration: TextDecoration.none,
                color: item.attention ? palette.destructive : palette.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
