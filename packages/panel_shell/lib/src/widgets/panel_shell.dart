import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:panel_shell/src/controller/panel_shell_controller.dart';
import 'package:panel_shell/src/event/panel_event.dart';
import 'package:panel_shell/src/input/panel_announcer.dart';
import 'package:panel_shell/src/input/panel_focus_policy.dart';
import 'package:panel_shell/src/input/panel_intents.dart';
import 'package:panel_shell/src/page/panel_page.dart';
import 'package:panel_shell/src/scroll/bottom_bar_visibility.dart';
import 'package:panel_shell/src/widgets/panel_bottom_bar.dart';
import 'package:panel_shell/src/widgets/panel_pager.dart';
import 'package:panel_shell/src/widgets/panel_search_field.dart';
import 'package:panel_shell/src/widgets/panel_type_tabs.dart';
import 'package:panel_shell/src/widgets/value_observable_builder.dart';

/// The host-independent panel: the search field above a pager of pages, with
/// the bottom bar (type tabs and the selected page's actions) floating over
/// it.
///
/// A projection of [controller]; it keeps no selection or search state of its
/// own, so unmounting it (a presentation switch) and mounting another shell
/// over the same controller restores the page, the query and the pages'
/// controllers. It positions nothing and reads no insets other than the
/// bottom padding it is given: where it sits, how tall it is and what it does
/// to the keyboard are for a presentation.
///
/// ## Requirements
///
/// A `ChromeThemeScope` and a `ChromeStringsScope` above it (both required,
/// asserting without them). A `ChromeMotionScope` is optional.
///
/// ## Input
///
/// Wraps its subtree in `Shortcuts` and `Actions` for [PanelSelectPageIntent],
/// [PanelSearchIntent] and `DismissIntent` (which closes search while it is
/// open and otherwise forwards to the enclosing handler, so Escape reaches a
/// popup that hosts the shell once search is closed). Pass
/// [shortcuts] to replace the default key bindings. Tab order inside the shell
/// is the page, the bottom bar, then the search field.
///
/// ## Announcements
///
/// Through [announcer]: panel opened or closed (from the controller's visible
/// state), the new page after a selection, and the count after a search
/// settles.
class PanelShell extends StatefulWidget {
  /// A shell showing the pages of [controller].
  const PanelShell({
    required this.controller,
    this.tabDisplay = PanelTabDisplay.label,
    this.shortcuts = PanelShortcuts.standard,
    this.focusPolicy = PanelFocusPolicy.none,
    this.announcer = const SemanticsServiceAnnouncer(),
    this.searchContextMenuBuilder,
    super.key,
  });

  /// The controller this shell projects.
  final PanelShellController controller;

  /// Whether the type tabs show names or icons.
  final PanelTabDisplay tabDisplay;

  /// The key bindings; defaults to [PanelShortcuts.standard].
  final Map<ShortcutActivator, Intent> shortcuts;

  /// What takes focus on open and where focus returns.
  final PanelFocusPolicy focusPolicy;

  /// Where announcements go.
  final PanelAnnouncer announcer;

  /// Builds the selection toolbar of the search field; null shows none.
  final EditableTextContextMenuBuilder? searchContextMenuBuilder;

  @override
  State<PanelShell> createState() => _PanelShellState();
}

class _PanelShellState extends State<PanelShell> {
  final _scope = FocusScopeNode(debugLabel: 'PanelShell');
  final _position = ValueNotifier<double>(0);
  final _dragging = ValueNotifier<bool>(false);
  final _barVisibility = BottomBarVisibility();

  PanelShellController get _shell => widget.controller;

  @override
  void initState() {
    super.initState();
    _bind(widget.controller);
  }

  @override
  void didUpdateWidget(PanelShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      _unbind(oldWidget.controller);
      _bind(widget.controller);
    }
  }

  @override
  void dispose() {
    _unbind(widget.controller);
    _barVisibility.dispose();
    _position.dispose();
    _dragging.dispose();
    _scope.dispose();
    super.dispose();
  }

  void _bind(PanelShellController controller) {
    _barVisibility
      ..pinnedHidden = controller.search.value.isOpen
      ..show();
    controller.search.addListener(_onSearch);
    controller.selectedPageId.addListener(_onPageSelected);
    controller.scrollActivity.addListener(_barVisibility.apply);
    controller.events.addListener(_onEvent);
    controller.searchResultCounts.addListener(_onResultCount);
    controller.visible.addListener(_onVisible);
  }

  void _unbind(PanelShellController controller) {
    controller.search.removeListener(_onSearch);
    controller.selectedPageId.removeListener(_onPageSelected);
    controller.scrollActivity.removeListener(_barVisibility.apply);
    controller.events.removeListener(_onEvent);
    controller.searchResultCounts.removeListener(_onResultCount);
    controller.visible.removeListener(_onVisible);
  }

  void _onSearch() {
    _barVisibility.pinnedHidden = _shell.search.value.isOpen;
  }

  void _onPageSelected() => _barVisibility.show();

  void _onEvent(PanelEvent event) {
    if (event case PageChanged(:final pageId)) {
      final strings = ChromeStringsScope.of(context);
      final page = _shell.pages.firstWhere((page) => page.id == pageId);
      widget.announcer.announce(
        context,
        strings.semantics.pageSelected(
          strings.panel.tabLabel(page.tab.labelKey),
        ),
      );
    }
  }

  void _onResultCount(int count) {
    final strings = ChromeStringsScope.of(context);
    widget.announcer.announce(
      context,
      strings.semantics.searchResultCount(count),
    );
  }

  void _onVisible() {
    final strings = ChromeStringsScope.of(context);
    final visible = _shell.visible.value;
    widget.announcer.announce(
      context,
      visible ? strings.semantics.panelOpened : strings.semantics.panelClosed,
    );
    final policy = widget.focusPolicy;
    if (visible) {
      if (policy.focusOnOpen) _scope.requestFocus();
    } else if (_scope.hasFocus) {
      policy.restoreTarget?.requestFocus();
    }
  }

  void _onAction(PanelPage page, PageAction action) =>
      _shell.invokeAction(page.id, action.id);

  @override
  Widget build(BuildContext context) {
    final panel = ChromeThemeScope.panelOf(context);
    final motion = ChromeMotionScope.of(context);
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final media = MediaQuery.of(context);

    return Shortcuts(
      shortcuts: widget.shortcuts,
      child: Actions(
        actions: <Type, Action<Intent>>{
          PanelSelectPageIntent: CallbackAction<PanelSelectPageIntent>(
            onInvoke: (intent) {
              _shell.selectPage(intent.pageId);
              return null;
            },
          ),
          PanelSearchIntent: CallbackAction<PanelSearchIntent>(
            onInvoke: (_) {
              _shell.openSearch();
              return null;
            },
          ),
          DismissIntent: _ShellDismissAction(_shell, context),
        },
        child: FocusScope(
          node: _scope,
          child: FocusTraversalGroup(
            policy: OrderedTraversalPolicy(),
            child: ColoredBox(
              color: panel.background,
              child: Column(
                children: [
                  ValueObservableBuilder<String>(
                    observable: _shell.selectedPageId,
                    builder: (context, _) => AnimatedSize(
                      duration: motion.durationOf(MotionRole.search),
                      curve: motion.curveOf(MotionRole.search),
                      alignment: AlignmentDirectional.topStart,
                      child: _shell.selectedPage.capabilities.search
                          ? FocusTraversalOrder(
                              order: const NumericFocusOrder(3),
                              child: PanelSearchField(
                                controller: _shell,
                                contextMenuBuilder:
                                    widget.searchContextMenuBuilder,
                              ),
                            )
                          : const SizedBox(width: double.infinity),
                    ),
                  ),
                  Expanded(
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: FocusTraversalOrder(
                            order: const NumericFocusOrder(1),
                            // The bar floats over the pages, so they are told
                            // to leave room for it the way they leave room
                            // for a system bar.
                            child: MediaQuery(
                              data: media.copyWith(
                                padding: media.padding.copyWith(
                                  bottom: safeBottom + PanelBottomBar.height,
                                ),
                              ),
                              child: PanelPager(
                                controller: _shell,
                                position: _position,
                                dragging: _dragging,
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: FocusTraversalOrder(
                            order: const NumericFocusOrder(2),
                            child: _bar(safeBottom, motion),
                          ),
                        ),
                      ],
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

  Widget _bar(double safeBottom, ChromeMotionData motion) {
    final reveal = motion.specOf(MotionRole.headerReveal);
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      // A control that takes focus must be seen: a keyboard user reaches the
      // bar while it is slid away.
      onFocusChange: (focused) {
        if (focused) _barVisibility.show();
      },
      child: ValueObservableBuilder<bool>(
        observable: _barVisibility.visible,
        builder: (context, visible) => TweenAnimationBuilder<double>(
          tween: Tween<double>(
            end: visible ? 0 : PanelBottomBar.hideSlide + safeBottom,
          ),
          duration: reveal.duration,
          curve: reveal.curve,
          builder: (context, y, child) =>
              Transform.translate(offset: Offset(0, y), child: child),
          child: Padding(
            padding: EdgeInsets.only(bottom: safeBottom),
            child: ValueObservableBuilder<String>(
              observable: _shell.selectedPageId,
              builder: (context, _) => PanelBottomBar(
                pages: _shell.pages,
                selected: _shell.selectedPage,
                position: _position,
                dragging: _dragging,
                display: widget.tabDisplay,
                onAction: _onAction,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Escape and system back: closes search while it is open, and otherwise
/// hands the intent to the nearest enclosing handler.
///
/// A disabled action would not do. `Shortcuts` resolves an intent to the
/// action nearest the focused widget and never looks further up when that one
/// is disabled, so a shell that merely disabled itself would swallow the key
/// instead of letting the popup that hosts it close. Forwarding from [_outer],
/// a context above the shell's own `Actions`, gives the order the shell
/// promises: search first, then the enclosing popup.
class _ShellDismissAction extends Action<DismissIntent> {
  _ShellDismissAction(this._shell, this._outer);

  final PanelShellController _shell;
  final BuildContext _outer;

  @override
  bool consumesKey(DismissIntent intent) =>
      _shell.search.value.isOpen ||
      Actions.maybeFind<DismissIntent>(_outer) != null;

  @override
  Object? invoke(DismissIntent intent) {
    if (_shell.handleBack()) return null;
    return Actions.maybeInvoke<DismissIntent>(_outer, intent);
  }
}
