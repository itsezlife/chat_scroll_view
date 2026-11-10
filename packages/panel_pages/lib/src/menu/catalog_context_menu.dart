import 'dart:math' as math;

import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:panel_pages/src/menu/catalog_menu_icons.dart';
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
///   closes, or with the page. A grid outside the panel (a pack sheet) has no
///   host and nothing to hold.
class CatalogContextMenuHost extends StatefulWidget {
  /// A host that holds auto-hide through [host] while its menu is up.
  const CatalogContextMenuHost({
    required this.host,
    required this.controller,
    required this.child,
    super.key,
  });

  /// The page's connection to the shell, or null for a grid outside the
  /// panel.
  final PanelPageHost? host;

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
  var _open = false;
  Offset _at = Offset.zero;
  var _moving = false;
  // Each opening plays its show from the start.
  var _opening = 0;
  // The menu is playing its hide; this takes it off the overlay at the end.
  VoidCallback? _hideOverlay;

  bool get _isOpen => _open;

  @override
  void initState() {
    super.initState();
    widget.controller._state = this;
    // A right-click opens the menu at once: its icons are decoded ahead.
    CatalogMenuIcons.warm();
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
    _markClosed();
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
    _open = true;
    _hold ??= widget.host?.holdAutoHide();
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
    _markClosed();
  }

  void _markClosed() {
    _open = false;
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
      if (!_moving) _markClosed();
    },
    onOpenRequested: (position, showOverlay) {
      _hideOverlay = null;
      _opening++;
      showOverlay();
    },
    // The menu leaves with the appear motion's hide, then the overlay goes.
    onCloseRequested: (hideOverlay) {
      if (!mounted || _moving) {
        hideOverlay();
        return;
      }
      // Closed from here on: the hold goes and the focus goes back as the
      // hide starts.
      _markClosed();
      setState(() => _hideOverlay = hideOverlay);
    },
    // In the text fields' tap group, barrier included: a press on the menu
    // is not a press outside the composer.
    overlayBuilder: (context, info) => TextFieldTapRegion(
      child: _MenuSurface(
        key: ValueKey(_opening),
        position: info.anchorRect.topLeft + (info.position ?? Offset.zero),
        overlaySize: info.overlaySize,
        entries: _entries,
        leaving: _hideOverlay != null,
        onHidden: () {
          final hide = _hideOverlay;
          _hideOverlay = null;
          hide?.call();
        },
        onChoose: _choose,
        onDismiss: _close,
      ),
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
    required this.leaving,
    required this.onHidden,
    required this.onChoose,
    required this.onDismiss,
    super.key,
  });

  final Offset position;
  final Size overlaySize;
  final List<CatalogMenuEntry> entries;
  final bool leaving;
  final VoidCallback onHidden;
  final ValueChanged<String> onChoose;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final textDirection = Directionality.of(context);
    final layout = _MenuLayout(
      position: position,
      textDirection: textDirection,
    );
    final palette = ChromeThemeScope.paletteOf(context);
    // A menu on its way out takes no press: the click goes where it points.
    return IgnorePointer(
      ignoring: leaving,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Listener(
            // Opaque: nothing below hears a press while the menu is up, so
            // the click that closes it picks nothing. Any button closes it.
            behavior: HitTestBehavior.opaque,
            onPointerDown: (_) => onDismiss(),
          ),
          CustomSingleChildLayout(
            delegate: layout,
            child: ChromeAppear(
              visible: !leaving,
              onHidden: onHidden,
              motion: const AppearMotion.grow(),
              origin: layout.originFor(
                overlaySize,
                CatalogContextMenuPanel.estimatedSize(entries),
              ),
              borderRadius: BorderRadius.circular(
                CatalogContextMenuPanel.radius,
              ),
              revealColor: palette.surfaceRaised,
              shadows: CatalogContextMenuPanel.shadowsOf(palette),
              child: CatalogContextMenuPanel(
                entries: entries,
                onChoose: onChoose,
                onDismiss: onDismiss,
                shadowed: false,
                leaving: leaving,
              ),
            ),
          ),
        ],
      ),
    );
  }
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

  /// The corner of a menu of [childSize] at the pointer, in a window of
  /// [size]: the one its grow starts from.
  Alignment originFor(Size size, Size childSize) {
    final at = getPositionForChild(size, childSize);
    return Alignment(
      at.dx + childSize.width / 2 < position.dx ? 1 : -1,
      at.dy + childSize.height / 2 < position.dy ? 1 : -1,
    );
  }

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
    this.shadowed = true,
    this.leaving = false,
    super.key,
  });

  /// Whether the menu is on its way out: it gives focus back at once, not
  /// when it leaves the tree.
  final bool leaving;

  /// Whether the card draws its own shadow; off when what shows it draws
  /// [shadowsOf] instead.
  final bool shadowed;

  /// The card's shadows in [palette].
  static List<BoxShadow> shadowsOf(ChromePalette palette) => [
    BoxShadow(
      color: palette.shadow.withValues(alpha: 0.28),
      blurRadius: 12,
      offset: const Offset(0, 3),
    ),
  ];

  /// The size of a menu of [entries] before it is laid out: its height, and
  /// its narrowest width.
  static Size estimatedSize(List<CatalogMenuEntry> entries) {
    var height = 2 * _padding;
    for (final entry in entries) {
      height += switch (entry) {
        CatalogMenuItem() => itemExtent,
        CatalogMenuSeparator() => 2 * _padding + 1,
      };
    }
    return Size(minWidth, height);
  }

  // Above the first item and below the last, and around a separator.
  static const double _padding = 4;

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

  /// From an icon's start to its label's: the preview menu's
  /// (43 logical pixels), so a right-click shows the preview's items as the
  /// preview does.
  static const double labelInset = 43;

  @override
  State<CatalogContextMenuPanel> createState() =>
      _CatalogContextMenuPanelState();
}

class _CatalogContextMenuPanelState extends State<CatalogContextMenuPanel> {
  final _scope = FocusScopeNode(debugLabel: 'CatalogContextMenu');
  // What had focus as the menu opened, which it gives focus back to.
  final FocusNode? _previous = FocusManager.instance.primaryFocus;
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
    // The keys go to the menu while it is up, but to the menu, not to an
    // item: like a native menu it opens with nothing highlighted, and the
    // first arrow press highlights the first (Down) or the last (Up) item. The
    // composer keeps its caret in its own node and has it back at the end.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _nodes.isNotEmpty) _scope.requestFocus();
    });
  }

  @override
  void didUpdateWidget(CatalogContextMenuPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.leaving && !oldWidget.leaving) _giveFocusBack();
    if (oldWidget.entries != widget.entries) {
      for (final node in _nodes) {
        node.dispose();
      }
      _nodes = _nodesFor(widget.entries);
    }
  }

  @override
  void dispose() {
    _giveFocusBack();
    for (final node in _nodes) {
      node.dispose();
    }
    _scope.dispose();
    super.dispose();
  }

  void _giveFocusBack() {
    final previous = _previous;
    if (!_scope.hasFocus || previous == null) return;
    // After this frame: the node that has focus may be leaving the tree.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (previous.context != null && previous.canRequestFocus) {
        previous.requestFocus();
      }
    });
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
                  boxShadow: widget.shadowed
                      ? CatalogContextMenuPanel.shadowsOf(palette)
                      : null,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minWidth: CatalogContextMenuPanel.minWidth,
                  ),
                  child: IntrinsicWidth(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: CatalogContextMenuPanel._padding,
                      ),
                      child: CatalogMenuIconScope(
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
                                    vertical: CatalogContextMenuPanel._padding,
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
        // The row keeps its own hover and focus wash; the ink adds the
        // press ripple.
        child: ChromeInk(
          kind: ChromeInkKind.pointer,
          color: ChromeCatalogTheme.pressInkOf(palette),
          onTap: widget.onChoose,
          child: Container(
            height: CatalogContextMenuPanel.itemExtent,
            alignment: AlignmentDirectional.centerStart,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            color: _hovered || _focused
                ? ChromeCatalogTheme.hoverWashOf(palette)
                : const Color(0x00000000),
            child: Row(
              children: [
                if (item.icon case final icon?)
                  SizedBox(
                    width: CatalogContextMenuPanel.labelInset,
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: ChromeIcon(
                        icon,
                        size: CatalogMenuIcons.sizeOf(icon),
                        color: item.attention
                            ? palette.destructive
                            : palette.iconIdle,
                      ),
                    ),
                  ),
                Flexible(
                  child: Text(
                    item.label,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: ChromeTypography.of(context).copyWith(
                      fontSize: 14,
                      height: 1.2,
                      color: item.attention
                          ? palette.destructive
                          : palette.onSurface,
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
