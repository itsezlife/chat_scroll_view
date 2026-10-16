import 'dart:async';

import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:panel_shell/src/controller/panel_shell_controller.dart';
import 'package:panel_shell/src/event/panel_event.dart';
import 'package:panel_shell/src/input/panel_announcer.dart';
import 'package:panel_shell/src/input/panel_focus_policy.dart';
import 'package:panel_shell/src/input/panel_intents.dart';
import 'package:panel_shell/src/page/panel_page.dart';
import 'package:panel_shell/src/scroll/bottom_bar_visibility.dart';
import 'package:panel_shell/src/widgets/listen_value_builder.dart';
import 'package:panel_shell/src/widgets/panel_bottom_bar.dart';
import 'package:panel_shell/src/widgets/panel_pager.dart';
import 'package:panel_shell/src/widgets/panel_search_field.dart';
import 'package:panel_shell/src/widgets/panel_type_tabs.dart';

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
    this.deferSearchField = false,
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

  /// Whether the search field mounts in the frame after the first one.
  ///
  /// A text field costs a frame of its own at 120 Hz, and the first frame of a
  /// panel already builds the page. A presentation that mounts the shell while
  /// nothing moves (a cold open) sets it, so the page, the field and the
  /// page's own strip arrive one frame apart; one that mounts the shell over
  /// content already on screen leaves it off, or the field would pop in.
  /// Read once, when the shell mounts.
  final bool deferSearchField;

  @override
  State<PanelShell> createState() => _PanelShellState();
}

class _PanelShellState extends State<PanelShell> {
  final _scope = FocusScopeNode(debugLabel: 'PanelShell');
  final _position = ValueNotifier<double>(0);
  final _dragging = ValueNotifier<bool>(false);
  final _barVisibility = BottomBarVisibility();
  final _subscriptions = <StreamSubscription<Object?>>[];
  late var _fieldMounted = !widget.deferSearchField;

  PanelShellController get _shell => widget.controller;

  @override
  void initState() {
    super.initState();
    _bind(widget.controller);
    if (!_fieldMounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _fieldMounted = true);
      });
    }
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
    controller.visible.addListener(_onVisible);
    _subscriptions.addAll([
      controller.scrollActivity.listen(_barVisibility.apply),
      controller.events.listen(_onEvent),
      controller.searchResultCounts.listen(_onResultCount),
    ]);
  }

  void _unbind(PanelShellController controller) {
    controller.search.removeListener(_onSearch);
    controller.selectedPageId.removeListener(_onPageSelected);
    controller.visible.removeListener(_onVisible);
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
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
                  ListenValueBuilder<String>(
                    listenable: _shell.selectedPageId,
                    builder: (context, _) => _searchSlot(motion),
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

  // The field comes and goes with the selected page. A zero duration (instant
  // motion speed) skips AnimatedSize: its render object re-dirties itself in
  // its own layout when it is asked to resize over no time, which is a
  // framework error, and there is nothing to animate anyway.
  Widget _searchSlot(ChromeMotionData motion) {
    final slot = _fieldMounted && _shell.selectedPage.capabilities.search
        ? FocusTraversalOrder(
            order: const NumericFocusOrder(3),
            child: PanelSearchField(
              controller: _shell,
              contextMenuBuilder: widget.searchContextMenuBuilder,
            ),
          )
        : const SizedBox(width: double.infinity);
    final duration = motion.durationOf(MotionRole.search);
    if (duration == Duration.zero) return slot;
    return AnimatedSize(
      duration: duration,
      curve: motion.curveOf(MotionRole.search),
      alignment: AlignmentDirectional.topStart,
      child: slot,
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
      child: ListenValueBuilder<bool>(
        listenable: _barVisibility.visible,
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
            child: ListenValueBuilder<String>(
              listenable: _shell.selectedPageId,
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
