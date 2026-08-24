import 'dart:async';
import 'dart:math' as math;

import 'package:chat_chrome/src/composer/chat_input_metrics.dart';
import 'package:chat_chrome/src/debug/chat_chrome_log.dart';
import 'package:chat_chrome/src/inset/chat_bottom_inset_controller.dart';
import 'package:chat_chrome/src/inset/keyboard_height_store.dart';
import 'package:chat_chrome/src/motion/keyboard_panel_motion.dart';
import 'package:chat_chrome/src/panel/emoji_deferred_recents.dart';
import 'package:chat_chrome/src/panel/emoji_page.dart';
import 'package:chat_chrome/src/panel/emoji_panel_allow.dart';
import 'package:chat_chrome/src/panel/emoji_panel_bottom_actions.dart';
import 'package:chat_chrome/src/panel/emoji_panel_bottom_bar.dart';
import 'package:chat_chrome/src/panel/emoji_panel_callbacks.dart';
import 'package:chat_chrome/src/panel/emoji_panel_labels.dart';
import 'package:chat_chrome/src/panel/emoji_panel_nav_bar_fade.dart';
import 'package:chat_chrome/src/panel/sticker_gif_stubs.dart';
import 'package:chat_chrome/src/theme/chat_chrome_colors.dart';
import 'package:emoji_data/emoji_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:panel_catalog/panel_catalog.dart';

/// Keyboard-replacement panel shell.
///
/// Owns open/close motion, type-tab [PageView], bottom chrome, search overlay,
/// and deferred recents commit. Bottom-bar hide/show listens to
/// [PanelCatalogController] scroll events from the emoji [EmojiPage] — not
/// [ScrollNotification]. Does **not** own catalog listeners or glyph grid
/// layout — those live on [EmojiPage] / [EmojiDataSource].
///
/// **Host wiring**: supply [controller], [store], [dataSource], insertion
/// ([onEmojiSelected]), and delete ([onBackspace]). Prefer
/// [EmojiPanelBottomActions.standard] for trailing bottom-bar actions.
///
/// **Open / close**: call [EmojiPanelState.open] / [EmojiPanelState.close] via
/// a [GlobalKey] (or keep [open] in sync). [close] with `waitForIme: true`
/// hands off to the soft keyboard while keeping the inset shell.
///
/// **Recents**: [EmojiDeferredRecents] commits frequency updates on open and
/// when leaving search — not on every pick while the panel is open.
class EmojiPanel extends StatefulWidget {
  /// Creates the panel shell.
  const EmojiPanel({
    required this.controller,
    required this.store,
    required this.allow,
    required this.dataSource,
    required this.onEmojiSelected,
    required this.onBackspace,
    this.onStickerSettings,
    this.callbacks = const EmojiPanelCallbacks(),
    this.bottomActions,
    this.labels = EmojiPanelLabels.english,
    this.open = false,
    this.onTabChanged,
    this.onOpenChanged,
    super.key,
  });

  /// Bottom-inset arbiter (panel occupancy vs IME).
  final ChatBottomInsetController controller;

  /// Persisted panel height prefs and last selected type tab.
  final KeyboardHeightStore store;

  /// Catalog, recents, search, and skin-tone data.
  final EmojiDataSource dataSource;

  /// Which type tabs are enabled (emoji / gifs / stickers).
  final EmojiPanelAllow allow;

  /// Host-localized type-tab titles and clear-recents copy.
  final EmojiPanelLabels labels;

  /// Insert emoji into the composer (host-owned text field).
  final ValueChanged<String> onEmojiSelected;

  /// Backspace on the emoji tab (also used for hold-to-repeat).
  final VoidCallback onBackspace;

  /// Stickers settings — prefer [EmojiPanelCallbacks.onStickerSettings].
  final VoidCallback? onStickerSettings;

  /// Secondary host hooks (clear-recents confirm, stickers settings, …).
  final EmojiPanelCallbacks callbacks;

  /// Trailing bottom-bar actions; defaults to [EmojiPanelBottomActions.standard].
  final EmojiPanelBottomActions? bottomActions;

  /// Declarative open flag — kept in sync with [EmojiPanelState.open] /
  /// [EmojiPanelState.close].
  ///
  /// When this drops to `false` while the panel is still visible (and not in
  /// keyboard handoff), the state schedules [EmojiPanelState.close].
  final bool open;

  /// Fired when the active type tab changes.
  final ValueChanged<EmojiPanelTab>? onTabChanged;

  /// Fired when open state changes (`true` after open starts, `false` on close).
  final ValueChanged<bool>? onOpenChanged;

  @override
  State<EmojiPanel> createState() => EmojiPanelState();
}

/// State for [EmojiPanel].
///
/// Hosts SHOULD call [open] / [close] / [handleBack] via a [GlobalKey]. Prefer
/// those over mutating [EmojiPanel.open] alone for animation control.
class EmojiPanelState extends State<EmojiPanel> with TickerProviderStateMixin {
  // --- Motion ---------------------------------------------------------------

  late final AnimationController _progress;

  /// True while a cold open animation is in flight.
  var _opening = false;

  /// True while a cold close animation is in flight.
  var _closing = false;

  /// Skip entrance animation when opening over a dismissing IME.
  var _replacingKeyboard = false;

  /// Occupancy height at the start of a cold close (`setPanelCloseOccupancy`).
  double _closeTarget = 0;

  /// Home-indicator band for close overshoot (`−safeBottom` at progress 0).
  ///
  /// Open uses live [MediaQuery.viewPadding] for the same `(1 − t) × band`
  /// slide so cold entrance starts below the screen, not in the safe band.
  double _closeSafeBottom = 0;

  /// Fixed paint height (panel target + safe). Content MUST NOT reflow.
  double _layoutHeight = 0;

  // --- Visibility / keyboard handoff ----------------------------------------

  /// Whether the panel chrome is mounted (or animating).
  var _visible = false;

  /// Keyboard handoff: shell stays, emoji grid hidden (`waitForIme` close).
  var _handoffToKeyboard = false;

  /// When false during handoff, [PageView] / chrome is [Offstage].
  var _contentVisible = true;

  // --- Type pager -----------------------------------------------------------

  late PageController _pageController;
  late List<EmojiPanelTab> _tabs;
  late final ValueNotifier<int> _pageIndex;
  late final ValueNotifier<double> _page;
  late final ValueNotifier<bool> _pageDragging;

  // --- Search ---------------------------------------------------------------

  final TextEditingController _search = TextEditingController();
  final FocusNode _searchFocus = FocusNode(debugLabel: 'EmojiPanelSearch');
  late final ValueNotifier<bool> _searchOpen;
  late final ValueNotifier<double> _searchFieldTy;
  late final ValueNotifier<bool> _searchFieldShadow;
  final GlobalKey<EmojiPageState> _emojiPageKey = GlobalKey<EmojiPageState>();
  AnimationController? _searchExpandAnim;

  // --- Recents --------------------------------------------------------------

  final EmojiDeferredRecents _deferredRecents = EmojiDeferredRecents();

  // --- Bottom bar -----------------------------------------------------------

  /// Bottom-tab visibility — bar slides down when false.
  late final ValueNotifier<bool> _bottomBarVisible;

  double _bottomScrollAccum = 0;
  DateTime? _shownBottomTabAfterClick;

  PanelCatalogController? _boundCatalogController;

  /// Short window after a strip/category tap — ignore bottom-bar hide.
  static const _tapTimeout = Duration(milliseconds: 100);

  // --- Test / host observables ----------------------------------------------

  /// Whether the panel is open, animating, or in keyboard handoff.
  bool get isOpen =>
      _visible || _handoffToKeyboard || widget.controller.isPanelOpen;

  /// Whether the bottom type-tab bar is shown.
  bool get bottomBarVisible => _bottomBarVisible.value;

  /// Active type tab.
  EmojiPanelTab get selectedTab => _tabs[_pageIndex.value];

  EmojiDataSource get _dataSource => widget.dataSource;

  VoidCallback? get _onStickerSettings =>
      widget.callbacks.onStickerSettings ?? widget.onStickerSettings;

  /// [PageController.initialPage] after last rebind (tests).
  @visibleForTesting
  int get debugPageControllerInitialPage => _pageController.initialPage;

  /// Selects a type tab programmatically (tests).
  @visibleForTesting
  Future<void> debugSelectPage(int index) => _commitPage(index, jump: true);

  /// Emoji grid state key (widget tests).
  @visibleForTesting
  GlobalKey<EmojiPageState> get debugEmojiPageKey => _emojiPageKey;

  /// Whether search mode is open (focused field + expanded height).
  bool get isSearchOpen => _searchOpen.value;

  /// Toggles search / bottom-bar visibility contract (tests).
  @visibleForTesting
  void debugToggleSearch() {
    if (_searchOpen.value) {
      unawaited(closeSearch());
    } else {
      unawaited(openSearch());
    }
  }

  /// Opens emoji search (expand height, pin field, hide strip / bottom bar).
  Future<void> openSearch() => _openSearch();

  /// Closes emoji search and collapses expanded height.
  ///
  /// [hideKeyboard]: when `false`, leaves IME focus transfer to the host
  /// (composer tap / keyboard button) so the soft keyboard does not flicker.
  Future<void> closeSearch({bool hideKeyboard = true}) =>
      _closeSearch(hideKeyboard: hideKeyboard);

  // --- Lifecycle ------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    _tabs = widget.allow.tabs;
    final initialPage = _initialPageIndex();
    _pageIndex = ValueNotifier<int>(initialPage);
    _page = ValueNotifier<double>(initialPage.toDouble());
    _pageDragging = ValueNotifier<bool>(false);
    _bottomBarVisible = ValueNotifier<bool>(true);
    _searchOpen = ValueNotifier<bool>(false);
    _searchFieldTy = ValueNotifier<double>(EmojiPage.gridPadTop);
    _searchFieldShadow = ValueNotifier<bool>(false);
    _searchFocus.addListener(_onSearchFocusChanged);
    _pageController = PageController(initialPage: initialPage);
    _pageController.addListener(_onPageControllerTick);
    _deferredRecents.commit(_dataSource);
    _progress = AnimationController(
      vsync: this,
      duration: KeyboardPanelMotion.duration,
    )..addListener(_onProgressTick);
    widget.controller.addListener(_onController);
    widget.controller.heightListenable.addListener(_onInsetHeight);
    chatChromeLog(
      'EmojiPanel initState open=${widget.open} tabs=${_tabs.length}',
    );
    if (widget.open) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.open) {
          unawaited(
            open(replacingKeyboard: widget.controller.openedReplacingIme),
          );
        }
      });
    }
  }

  @override
  void didUpdateWidget(EmojiPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.allow != widget.allow) {
      _tabs = widget.allow.tabs;
      if (_pageIndex.value >= _tabs.length) _pageIndex.value = 0;
    }
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_onController);
      oldWidget.controller.heightListenable.removeListener(_onInsetHeight);
      widget.controller.addListener(_onController);
      widget.controller.heightListenable.addListener(_onInsetHeight);
    }
    if (oldWidget.open != widget.open) {
      chatChromeLog(
        'EmojiPanel didUpdateWidget open ${oldWidget.open}→${widget.open}',
      );
      // Host drives open/close via GlobalKey. Only sync close here if the
      // declarative flag dropped while we are still visibly open (back / etc.).
      final wantOpen = widget.open;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (!wantOpen && (_visible || _handoffToKeyboard) && !_closing) {
          if (_handoffToKeyboard) {
            // Host clears `open` during keyboard handoff — shell stays up.
            return;
          }
          unawaited(close());
        }
      });
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onController);
    widget.controller.heightListenable.removeListener(_onInsetHeight);
    _progress
      ..removeListener(_onProgressTick)
      ..dispose();
    _pageController
      ..removeListener(_onPageControllerTick)
      ..dispose();
    _searchExpandAnim?.dispose();
    _searchFocus
      ..removeListener(_onSearchFocusChanged)
      ..dispose();
    _search.dispose();
    _page.dispose();
    _pageIndex.dispose();
    _pageDragging.dispose();
    _bottomBarVisible.dispose();
    _searchOpen.dispose();
    _searchFieldTy.dispose();
    _searchFieldShadow.dispose();
    _unbindCatalogScroll();
    super.dispose();
  }

  // --- Pager ---------------------------------------------------------------

  void _onPageControllerTick() {
    final page = _pageController.page;
    if (page == null) return;
    if (page != _page.value) {
      _page.value = page;
    }
    // Mid-swipe / mid-animate: freeze type-tab indicator settle animation.
    final fraction = (page - page.roundToDouble()).abs();
    final dragging = fraction > 0.001;
    if (_pageDragging.value != dragging) {
      _pageDragging.value = dragging;
    }
  }

  /// Remount [PageView] at [index] when the controller has no clients.
  ///
  /// `jumpToPage` does not update [PageController.initialPage], so a disposed
  /// pager would otherwise restore the ctor page on the next mount.
  void _rebindPageController(int index) {
    if (_pageController.hasClients) return;
    if (_pageController.initialPage == index) return;
    _pageController
      ..removeListener(_onPageControllerTick)
      ..dispose();
    _pageController = PageController(initialPage: index)
      ..addListener(_onPageControllerTick);
    _page.value = index.toDouble();
  }

  void _ensurePageSyncedAfterOpen() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_visible) return;
      _syncCatalogScrollBinding();
      if (!_pageController.hasClients) return;
      final current = _pageController.page?.round() ?? _pageIndex.value;
      if (current == _pageIndex.value) return;
      _pageController.jumpToPage(_pageIndex.value);
      _page.value = _pageIndex.value.toDouble();
      _pageDragging.value = false;
    });
  }

  int _initialPageIndex() {
    if (_tabs.isEmpty) return 0;
    final preferred = EmojiPanelTabPrefs.fromPrefs(widget.store.selectedPage);
    final idx = _tabs.indexOf(preferred);
    return idx >= 0 ? idx : 0;
  }

  // --- Inset controller / handoff -------------------------------------------

  void _onController() {
    if (_opening || _closing) return;
    _maybeDismissHandoffShell();
    if (_handoffToKeyboard) return;

    if (!widget.controller.isPanelOpen && (_visible || _progress.value > 0)) {
      chatChromeLog('EmojiPanel controller cleared panel → sync close');
      unawaited(close(notifyController: false));
    }
  }

  void _onInsetHeight() {
    if (!_handoffToKeyboard) return;
    _maybeDismissHandoffShell();
  }

  void _finishHandoffShell() {
    if (!_handoffToKeyboard) return;
    _handoffToKeyboard = false;
    _visible = false;
    _contentVisible = true;
    _progress.value = 0;
  }

  void _maybeDismissHandoffShell() {
    if (!_handoffToKeyboard || widget.controller.isHoldingForIme) return;
    if (mounted) {
      setState(_finishHandoffShell);
    }
  }

  /// Handoff hides the grid but keeps the shell; reopen MUST restore chrome.
  void _restoreChromeForOpen() {
    if (!_handoffToKeyboard && _contentVisible) return;
    _handoffToKeyboard = false;
    _contentVisible = true;
  }

  void _onProgressTick() {
    if (_handoffToKeyboard) return;
    if (_replacingKeyboard && !_closing) return;
    if (!_visible && _progress.value == 0) return;

    final target = _closing ? _closeTarget : widget.controller.panelTarget;
    if (target <= 0 && !_closing) return;

    if (!_closing && !widget.controller.isPanelOpen) return;

    if (_closing) {
      // Inset stays ≥ 0 (target → 0). Safe-area exit is a local Transform.
      widget.controller.setPanelCloseOccupancy(_progress.value * _closeTarget);
    } else {
      widget.controller.setPanelOccupancy(_progress.value * target);
    }
  }

  // --- Open / close / back --------------------------------------------------

  /// Opens the panel. Prefer calling this from the host after claiming the
  /// inset slot ([ChatBottomInsetController.openPanel]).
  ///
  /// [replacingKeyboard]: skip entrance animation when IME was up (REPLACE).
  /// No-ops when tabs are empty or an open is already in flight. Commits
  /// deferred recents and rebinds the pager before the [PageView] mounts.
  Future<void> open({bool replacingKeyboard = false}) async {
    chatChromeLog(
      'EmojiPanel.open enter replacing=$replacingKeyboard '
      'visible=$_visible progress=${_progress.value} '
      'opening=$_opening closing=$_closing tabs=${_tabs.length} '
      'controllerOpen=${widget.controller.isPanelOpen} '
      'target=${widget.controller.panelTarget} '
      'published=${widget.controller.height}',
    );
    if (_tabs.isEmpty) {
      chatChromeLog('EmojiPanel.open ABORT empty tabs');
      return;
    }
    if (_opening) {
      chatChromeLog('EmojiPanel.open ABORT already opening');
      return;
    }

    final healChrome = _handoffToKeyboard || !_contentVisible;
    _restoreChromeForOpen();

    if (_visible && _progress.value >= 1 && widget.controller.isPanelOpen) {
      chatChromeLog(
        'EmojiPanel.open ABORT already fully open heal=$healChrome',
      );
      if (healChrome && mounted) {
        setState(() {});
      }
      return;
    }

    _opening = true;
    _closing = false;
    _replacingKeyboard = replacingKeyboard;

    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final safeBottom = MediaQuery.viewPaddingOf(context).bottom;
    if (!widget.controller.isPanelOpen) {
      chatChromeLog('EmojiPanel.open claiming slot (host did not)');
      widget.controller.openPanel(landscape: landscape);
      _replacingKeyboard = widget.controller.openedReplacingIme;
    }

    _layoutHeight = widget.controller.panelTarget + safeBottom;
    if (_layoutHeight < safeBottom + 96) {
      _layoutHeight =
          widget.controller.panelTargetHeight(landscape: landscape) +
          safeBottom;
    }

    // Pager was torn down while closed — rebuild [PageController] at [_pageIndex]
    // before [PageView] mounts (`initialPage` is not updated by `jumpToPage`).
    _rebindPageController(_pageIndex.value);
    // Apply deferred frequency-map changes from the previous session.
    _deferredRecents.commit(_dataSource);

    if (!_visible) {
      setState(() {
        _visible = true;
        _bottomBarVisible.value = true;
        _bottomScrollAccum = 0;
      });
    } else if (mounted) {
      setState(() {});
    }
    widget.onOpenChanged?.call(true);

    if (_replacingKeyboard) {
      chatChromeLog('EmojiPanel.open REPLACE snap progress=1');
      _progress.value = 1;
      widget.controller.setPanelOccupancy(widget.controller.panelTarget);
      _opening = false;
      _ensurePageSyncedAfterOpen();
      return;
    }

    chatChromeLog('EmojiPanel.open COLD animate 0→1');
    _progress.value = 0;
    widget.controller.setPanelOccupancy(0);
    await Future<void>.delayed(KeyboardPanelMotion.startDelay);
    if (!mounted || _closing) {
      chatChromeLog(
        'EmojiPanel.open COLD aborted after delay '
        'mounted=$mounted closing=$_closing',
      );
      _opening = false;
      return;
    }
    try {
      await _progress.animateTo(1, curve: KeyboardPanelMotion.curve);
      chatChromeLog(
        'EmojiPanel.open COLD done progress=${_progress.value} '
        'published=${widget.controller.height}',
      );
    } catch (e, st) {
      chatChromeLog('EmojiPanel.open COLD animate error $e\n$st');
    } finally {
      _opening = false;
      _ensurePageSyncedAfterOpen();
    }
  }

  /// Closes the panel.
  ///
  /// [waitForIme]: keyboard handoff — hide emoji chrome, keep shell + inset
  /// hold until IME takes over. [notifyController]: whether to call
  /// [ChatBottomInsetController.closePanel]. Cold close animates occupancy
  /// then unmounts; search state is cleared.
  Future<void> close({
    bool notifyController = true,
    bool waitForIme = false,
  }) async {
    chatChromeLog(
      'EmojiPanel.close waitForIme=$waitForIme notify=$notifyController '
      'progress=${_progress.value} published=${widget.controller.height}',
    );
    if (_closing) return;

    if (_handoffToKeyboard) {
      if (waitForIme) {
        chatChromeLog('EmojiPanel.close handoff duplicate → finish shell');
        widget.onOpenChanged?.call(false);
        if (widget.controller.isHoldingForIme) {
          widget.controller.closePanel(waitForIme: false);
        }
        if (mounted) {
          setState(_finishHandoffShell);
        } else {
          _finishHandoffShell();
        }
        return;
      }
      _handoffToKeyboard = false;
      _contentVisible = true;
    }

    _opening = false;
    widget.onOpenChanged?.call(false);

    if (waitForIme) {
      // Keyboard handoff: hide emoji chrome, keep panel shell + inset hold.
      _handoffToKeyboard = true;
      _contentVisible = false;
      if (notifyController) {
        widget.controller.closePanel(waitForIme: true);
      }
      if (mounted) {
        setState(() {});
      }
      chatChromeLog(
        'EmojiPanel.close handoff shell-only progress=${_progress.value}',
      );
      return;
    }

    _closing = true;
    // Cold dismiss: animate occupancy target → −safeBottom, then release.
    _closeSafeBottom = MediaQuery.viewPaddingOf(context).bottom;
    _closeTarget = widget.controller.isPanelOpen
        ? (widget.controller.panelTarget > 0
              ? widget.controller.panelTarget
              : math.max(0.0, widget.controller.height))
        : math.max(0.0, widget.controller.height);
    if (_closeTarget <= 0) {
      _closeTarget = widget.controller.panelTargetHeight(
        landscape: MediaQuery.orientationOf(context) == Orientation.landscape,
      );
    }
    if (_layoutHeight <= 0) {
      _layoutHeight = _closeTarget + _closeSafeBottom;
    }
    _replacingKeyboard = false;
    _contentVisible = true;

    try {
      await _progress.animateTo(0, curve: KeyboardPanelMotion.curve);
      chatChromeLog(
        'EmojiPanel.close COLD done progress=${_progress.value} '
        'published=${widget.controller.height}',
      );
    } catch (e, st) {
      chatChromeLog('EmojiPanel.close animate error $e\n$st');
    }

    if (notifyController) {
      widget.controller.closePanel(waitForIme: false);
    }

    if (!mounted) return;
    setState(() {
      _visible = false;
      _closing = false;
      _handoffToKeyboard = false;
      _contentVisible = true;
      _searchOpen.value = false;
      _search.clear();
      _searchFocus.unfocus();
      widget.controller.collapsePanelFromSearch();
    });
    chatChromeLog(
      'EmojiPanel.close done published=${widget.controller.height}',
    );
  }

  /// Back-press contract: search IME → search mode → panel → unhandled.
  ///
  /// While search is open and the soft keyboard is up, the first back only
  /// dismisses IME and **keeps** search focus (Telegram). The next back exits
  /// search mode.
  Future<bool> handleBack() async {
    if (_searchOpen.value) {
      final imeUp =
          MediaQuery.viewInsetsOf(context).bottom > 1 ||
          widget.controller.imeHeight > 1;
      if (imeUp) {
        await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
        return true;
      }
      await _closeSearch(hideKeyboard: true);
      return true;
    }
    if (isOpen) {
      await close();
      return true;
    }
    return false;
  }

  // --- Picks / recents ------------------------------------------------------

  Future<void> _onEmoji(String glyph, {required EmojiPickSource source}) async {
    widget.onEmojiSelected(glyph);
    await _dataSource.recordPick(
      UnicodeEmojiItem(
        glyph: glyph,
        keywords: const <String>[],
        supportsSkinTone: EmojiSkinTone.supports(glyph),
      ),
      source: source,
    );
  }

  Future<void> _onClearRecents() async {
    await _dataSource.clearRecents();
    if (mounted) {
      setState(_deferredRecents.clear);
    }
  }

  Future<void> _onRequestClearRecents() async {
    if (!mounted) return;
    await widget.callbacks.onClearRecents(
      EmojiClearRecentsRequest(
        context: context,
        labels: widget.labels,
        clear: _onClearRecents,
      ),
    );
  }

  // --- Bottom bar visibility ------------------------------------------------

  void _bindCatalogScroll(PanelCatalogController controller) {
    if (identical(_boundCatalogController, controller)) return;
    _unbindCatalogScroll();
    _boundCatalogController = controller;
    controller.addScrollListener(_onCatalogScroll);
  }

  void _unbindCatalogScroll() {
    _boundCatalogController?.removeScrollListener(_onCatalogScroll);
    _boundCatalogController = null;
  }

  void _syncCatalogScrollBinding() {
    final page = _emojiPageKey.currentState;
    final controller = page?.catalogController;
    if (controller == null) {
      _unbindCatalogScroll();
      return;
    }
    _bindCatalogScroll(controller);
  }

  void _onCatalogScroll(PanelCatalogScrollEvent event) {
    switch (event) {
      case PanelCatalogSectionJumpStart():
        _bottomScrollAccum = 0;
        _markBottomTabAfterClick();
      case PanelCatalogSectionJumpEnd():
        _markBottomTabAfterClick();
        _maybeShowBottomTabAtCatalogEdge();
      case PanelCatalogViewportScrolled(:final delta):
        _checkBottomTabScroll(delta);
      case PanelCatalogOffsetChanged():
      case PanelCatalogProgrammaticJump():
      case PanelCatalogAnimateEnd():
      case PanelCatalogFlingEnd():
        _maybeShowBottomTabAtCatalogEdge();
      default:
        break;
    }
  }

  void _maybeShowBottomTabAtCatalogEdge() {
    final page = _emojiPageKey.currentState;
    if (page == null || page.catalogMaxScrollOffset <= 0) return;
    final offset = page.catalogScrollOffset;
    final max = page.catalogMaxScrollOffset;
    final atTop = offset <= 0.5;
    final atBottom = offset >= max - 0.5;
    if (atTop || atBottom) {
      _showBottomTab(true);
    }
  }

  void _markBottomTabAfterClick() {
    _shownBottomTabAfterClick = DateTime.now();
    _showBottomTab(true);
  }

  void _checkBottomTabScroll(double dy) {
    if (_boundCatalogController?.isSectionJumpActive ?? false) return;

    final afterClick = _shownBottomTabAfterClick;
    if (afterClick != null &&
        DateTime.now().difference(afterClick) < _tapTimeout) {
      return;
    }

    _bottomScrollAccum += dy;
    final offset = EmojiPanelBottomBar.scrollToggleOffset;

    if (_bottomScrollAccum >= offset) {
      _showBottomTab(false);
    } else if (_bottomScrollAccum <= -offset) {
      _showBottomTab(true);
    } else if ((_bottomBarVisible.value && _bottomScrollAccum < 0) ||
        (!_bottomBarVisible.value && _bottomScrollAccum > 0)) {
      _bottomScrollAccum = 0;
    }
  }

  void _showBottomTab(bool show) {
    _bottomScrollAccum = 0;
    if (_searchOpen.value) {
      show = false;
    }
    if (show == _bottomBarVisible.value) return;
    _bottomBarVisible.value = show;
  }

  // --- Search / type tab ----------------------------------------------------

  void _onSearchFocusChanged() {
    if (_searchFocus.hasFocus && !_searchOpen.value) {
      unawaited(_openSearch());
    }
  }

  double _availableMaxForSearch() {
    final mq = MediaQuery.of(context);
    final size = mq.size;
    final safeTop = mq.viewPadding.top;
    final safeBottom = mq.viewPadding.bottom;
    // originalViewHeight − status − nav − dp(6) − actionBar − enterView.
    // Approximate: full screen minus status, nav, and a composer band (~48+).
    const composerBand = 56.0;
    const slack = 6.0;
    return math.max(
      widget.controller.panelBaseTarget,
      size.height - safeTop - safeBottom - composerBand - slack,
    );
  }

  Future<void> _openSearch() async {
    if (_searchOpen.value) {
      if (!_searchFocus.hasFocus) {
        _searchFocus.requestFocus();
      }
      return;
    }
    _searchOpen.value = true;
    _showBottomTab(false);
    _searchFieldTy.value = 0;
    if (mounted) setState(() {});

    final from = widget.controller.panelTarget;
    final avail = _availableMaxForSearch();
    final to = widget.controller.expandPanelForSearch(availableMax: avail);
    await _animateSearchHeight(from: from, to: to);

    if (!mounted) return;
    if (!_searchFocus.hasFocus) {
      _searchFocus.requestFocus();
    }
  }

  Future<void> _closeSearch({bool hideKeyboard = true}) async {
    if (!_searchOpen.value && !widget.controller.isSearchExpanded) {
      return;
    }
    if (hideKeyboard) {
      _searchFocus.unfocus();
    }
    _searchOpen.value = false;
    _search.clear();
    _deferredRecents.commit(_dataSource);

    final from = widget.controller.panelTarget;
    final to = widget.controller.panelBaseTarget;
    await _animateSearchHeight(from: from, to: to);
    widget.controller.collapsePanelFromSearch();

    if (!mounted) return;
    _showBottomTab(true);
    setState(() {});
    if (hideKeyboard) {
      // Stay on emoji panel — host restores composer focus (IME stays down).
      widget.callbacks.onSearchClosed?.call();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _emojiPageKey.currentState?.revealStrip();
    });
  }

  Future<void> _animateSearchHeight({
    required double from,
    required double to,
  }) async {
    if ((from - to).abs() < 0.5) {
      final safeBottom = MediaQuery.viewPaddingOf(context).bottom;
      _layoutHeight = to + safeBottom;
      widget.controller.setPanelOccupancy(to);
      if (mounted) setState(() {});
      return;
    }

    _searchExpandAnim?.dispose();
    final controller = AnimationController(
      vsync: this,
      duration: KeyboardPanelMotion.searchExpandDuration,
    );
    _searchExpandAnim = controller;
    final curved = CurvedAnimation(
      parent: controller,
      curve: KeyboardPanelMotion.curve,
    );
    final safeBottom = MediaQuery.viewPaddingOf(context).bottom;

    void tick() {
      final h = from + (to - from) * curved.value;
      widget.controller.setPanelOccupancy(h);
      _layoutHeight = h + safeBottom;
      if (mounted) setState(() {});
    }

    curved.addListener(tick);
    try {
      await controller.forward();
      widget.controller.setPanelOccupancy(to);
      _layoutHeight = to + safeBottom;
      if (mounted) setState(() {});
    } finally {
      curved.removeListener(tick);
      controller.dispose();
      if (identical(_searchExpandAnim, controller)) {
        _searchExpandAnim = null;
      }
    }
  }

  /// Updates type-tab selection, pager, and prefs.
  ///
  /// Continuous [_page] is owned by [_onPageControllerTick] during swipes.
  /// [PageView.onPageChanged] only commits [_pageIndex]; forcing `_page = index`
  /// here would teleport the type-tab indicator mid-drag.
  ///
  /// Reselecting the emoji tab calls [EmojiPageState.scrollToFirstCategory]
  /// without exiting search mode.
  Future<void> _commitPage(int index, {required bool jump}) async {
    if (index < 0 || index >= _tabs.length) return;

    final changed = index != _pageIndex.value;
    if (!changed && jump && _tabs[index] == EmojiPanelTab.emoji) {
      _showBottomTab(true);
      _syncCatalogScrollBinding();
      await _emojiPageKey.currentState?.scrollToFirstCategory();
      return;
    }

    if (changed) {
      _pageIndex.value = index;
      if (jump) {
        _page.value = index.toDouble();
      }
    }

    if (jump &&
        _pageController.hasClients &&
        (_pageController.page?.round() ?? _pageIndex.value) != index) {
      _pageController.jumpToPage(index);
      _pageDragging.value = false;
    }

    _showBottomTab(true);
    if (_tabs[index] == EmojiPanelTab.emoji) {
      _syncCatalogScrollBinding();
    }
    final tab = _tabs[index];
    if (changed) {
      widget.onTabChanged?.call(tab);
    }
    await widget.store.setSelectedPage(tab.prefsPage);
  }

  Future<void> _onPageChanged(int index) async {
    await _commitPage(index, jump: false);
  }

  // --- Build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (!_visible && !_handoffToKeyboard) {
      return const SizedBox.shrink();
    }
    final mq = MediaQuery.of(context);
    final safeBottom = mq.viewPadding.bottom;
    final colors = ChatChromeTheme.of(context);
    final drawContent = _contentVisible && !_handoffToKeyboard;
    final layoutH = _layoutHeight > 0
        ? _layoutHeight
        : widget.controller.panelTarget + safeBottom;

    // Freeze bottom viewInsets/padding so lists do not reflow while the OS
    // keyboard dismisses under a REPLACE open (keep a fixed sheet height).
    final frozen = mq.copyWith(
      viewInsets: mq.viewInsets.copyWith(bottom: 0),
      padding: mq.padding.copyWith(bottom: safeBottom),
    );

    // Parent slot = published + host safeBottom (≥ safeBottom, never negative).
    // Fixed [layoutH] bottom-aligned → shrink clips from the top (slide up).
    // [safeSlide] keeps the sheet fully below the physical screen until
    // occupancy grows: without it, progress=0 parks the panel bottom in the
    // transparent safe-area band (host slot is still `0 + safeBottom`).
    // Close uses the same factor so the last strip clears the home indicator.
    return MediaQuery(
      data: frozen,
      child: AnimatedBuilder(
        animation: _progress,
        builder: (context, child) {
          final safeBand = _closing && _closeSafeBottom > 0
              ? _closeSafeBottom
              : safeBottom;
          final safeSlide = (1.0 - _progress.value) * safeBand;
          return ClipRect(
            child: Transform.translate(
              offset: Offset(0, safeSlide),
              child: Align(alignment: Alignment.bottomCenter, child: child),
            ),
          );
        },
        child: SizedBox(
          height: layoutH > 0 ? layoutH : null,
          width: double.infinity,
          child: Material(
            color: colors.panelBackground,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(ChatInputMetrics.keyboardRadius),
            ),
            clipBehavior: Clip.hardEdge,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final h = constraints.maxHeight;
                final showBottom = h >= 96;
                return Offstage(
                  offstage: !drawContent,
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      PageView(
                        controller: _pageController,
                        onPageChanged: _onPageChanged,
                        children: <Widget>[
                          for (final tab in _tabs)
                            switch (tab) {
                              EmojiPanelTab.emoji => EmojiPage(
                                key: _emojiPageKey,
                                dataSource: widget.dataSource,
                                recents: _deferredRecents.glyphs,
                                recentlyUsedLabel: widget.labels.recentlyUsed,
                                searchController: _search,
                                searchModeListenable: _searchOpen,
                                searchFieldTranslationY: _searchFieldTy,
                                searchFieldShadow: _searchFieldShadow,
                                searchFocusNode: _searchFocus,
                                searchHintText: widget.labels.searchHint,
                                searchResultsLabel: widget.labels.searchResults,
                                searchEmptyLabel: widget.labels.searchEmpty,
                                onOpenSearch: () {
                                  unawaited(_openSearch());
                                },
                                onEmojiSelected: _onEmoji,
                                onClearRecents: _onRequestClearRecents,
                              ),
                              EmojiPanelTab.gifs => const GifPageStub(),
                              EmojiPanelTab.stickers => const StickerPageStub(),
                            },
                        ],
                      ),
                      // Softens glyphs that scroll into the nav inset
                      // (clipToPadding=false). Over grid, under bottom bar.
                      if (safeBottom > 0)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: EmojiPanelNavBarFade(
                            height: safeBottom,
                            color: colors.panelBackground,
                          ),
                        ),
                      if (showBottom)
                        Positioned(
                          left: 0,
                          right: 0,
                          // Sit in the safe band via padding; hide slide must
                          // include [safeBottom] so the bar clears the screen
                          // (not park in the transparent inset).
                          bottom: 0,
                          child: ValueListenableBuilder<bool>(
                            valueListenable: _bottomBarVisible,
                            builder: (context, bottomBarVisible, child) {
                              return TweenAnimationBuilder<double>(
                                tween: Tween<double>(
                                  end: bottomBarVisible
                                      ? 0
                                      : EmojiPanelBottomBar.hideSlide +
                                            safeBottom,
                                ),
                                duration:
                                    EmojiPanelBottomBar.visibilityDuration,
                                curve: Curves.easeOutQuint,
                                builder: (context, y, animatedChild) =>
                                    Transform.translate(
                                      offset: Offset(0, y),
                                      child: animatedChild,
                                    ),
                                child: child,
                              );
                            },
                            child: Padding(
                              padding: EdgeInsets.only(bottom: safeBottom),
                              child: ListenableBuilder(
                                listenable: Listenable.merge(<Listenable>[
                                  _page,
                                  _pageDragging,
                                  _pageIndex,
                                ]),
                                builder: (context, _) {
                                  return EmojiPanelBottomBar(
                                    tabs: _tabs,
                                    page: _page.value,
                                    selectedTab: _tabs[_pageIndex.value],
                                    pageDragging: _pageDragging.value,
                                    labels: widget.labels,
                                    actions:
                                        widget.bottomActions ??
                                        EmojiPanelBottomActions.standard(
                                          onBackspace: widget.onBackspace,
                                          onStickerSettings: _onStickerSettings,
                                        ),
                                    onSelectTab: (i) {
                                      // Jump type tab without pager smooth
                                      // scroll — indicator settles separately.
                                      _markBottomTabAfterClick();
                                      _pageDragging.value = false;
                                      unawaited(_commitPage(i, jump: true));
                                    },
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Deletes one extended grapheme cluster at the caret, or the selection.
///
/// Hosts typically wire this to [EmojiPanel.onBackspace] /
/// [EmojiPanelBottomActions]. No-ops when the field is empty or the caret
/// is at offset `0` with a collapsed selection.
void emojiBackspace(TextEditingController controller) {
  final value = controller.value;
  final text = value.text;
  if (text.isEmpty) return;

  final selection = value.selection;
  if (!selection.isValid) {
    final next = text.characters.skipLast(1).toString();
    controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
    return;
  }

  if (!selection.isCollapsed) {
    final next = text.replaceRange(selection.start, selection.end, '');
    controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: selection.start),
    );
    return;
  }

  final caret = selection.baseOffset;
  if (caret <= 0) return;

  final before = text.substring(0, caret);
  final after = text.substring(caret);
  final trimmed = before.characters.skipLast(1).toString();
  final next = trimmed + after;
  controller.value = TextEditingValue(
    text: next,
    selection: TextSelection.collapsed(offset: trimmed.length),
  );
}
