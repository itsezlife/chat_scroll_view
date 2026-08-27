import 'dart:async';
import 'dart:math' as math;

import 'package:chat_chrome/src/composer/chat_input_metrics.dart';
import 'package:chat_chrome/src/debug/chat_chrome_log.dart';
import 'package:chat_chrome/src/inset/chat_bottom_inset_controller.dart';
import 'package:chat_chrome/src/motion/keyboard_panel_motion.dart';
import 'package:chat_chrome/src/panel/emoji_deferred_recents.dart';
import 'package:chat_chrome/src/panel/emoji_page.dart';
import 'package:chat_chrome/src/panel/keyboard_panel_allow.dart';
import 'package:chat_chrome/src/panel/keyboard_panel_bottom_actions.dart';
import 'package:chat_chrome/src/panel/keyboard_panel_bottom_bar.dart';
import 'package:chat_chrome/src/panel/keyboard_panel_callbacks.dart';
import 'package:chat_chrome/src/panel/keyboard_panel_labels.dart';
import 'package:chat_chrome/src/panel/keyboard_panel_nav_bar_fade.dart';
import 'package:chat_chrome/src/panel/keyboard_panel_controller.dart';
import 'package:chat_chrome/src/panel/sticker_gif_stubs.dart';
import 'package:chat_chrome/src/theme/chat_chrome_colors.dart';
import 'package:emoji_data/emoji_data.dart';
import 'package:flutter/material.dart';
import 'package:panel_catalog/panel_catalog.dart';

/// Keyboard-replacement panel shell.
///
/// ## Ownership
///
/// **Owns:** open/close motion projection, type-tab [PageView], bottom chrome,
/// search overlay widgets/focus, and deferred recents commit timing. Bottom-bar
/// hide/show listens to [PanelCatalogController] scroll events from the emoji
/// [EmojiPage] — not [ScrollNotification].
///
/// **Does not own:** desired open / search / type-tab SoT (that is
/// [KeyboardPanelController]); inset occupancy math ([ChatBottomInsetController]);
/// catalog listeners or glyph grid layout ([EmojiPage] / [EmojiDataSource]);
/// composer text; soft-IME dismiss-before-search-exit (host — needs
/// [BuildContext] / text-input channels).
///
/// ## Controller projection
///
/// Hosts drive chrome via [KeyboardPanelController] only — no GlobalKey on this
/// widget's State. On mount the private State binds projection handlers,
/// projects cold / replace-IME / wait-for-IME handoff, search expand/collapse,
/// and the type pager, and unbinds on dispose without disposing the host
/// controller. Insert/backspace and [KeyboardPanelCallbacks] stay on this widget.
///
/// ## Recents
///
/// [EmojiDeferredRecents] commits frequency updates on open and when leaving
/// search — not on every pick while the panel is open.
class KeyboardPanel extends StatefulWidget {
  /// Creates the panel shell.
  const KeyboardPanel({
    required this.controller,
    required this.allow,
    required this.dataSource,
    required this.onEmojiSelected,
    required this.onBackspace,
    this.callbacks = const KeyboardPanelCallbacks(),
    this.bottomActions,
    this.labels = KeyboardPanelLabels.english,
    super.key,
  });

  /// Host-owned chrome SoT (open/search/tab + inset claim/release + panel store).
  final KeyboardPanelController controller;

  /// Catalog, recents, search, and skin-tone data.
  final EmojiDataSource dataSource;

  /// Which type tabs are enabled (emoji / gifs / stickers).
  final KeyboardPanelAllow allow;

  /// Host-localized type-tab titles and clear-recents copy.
  final KeyboardPanelLabels labels;

  /// Insert emoji into the composer (host-owned text field).
  final ValueChanged<String> onEmojiSelected;

  /// Backspace on the emoji tab (also used for hold-to-repeat).
  final VoidCallback onBackspace;

  /// Secondary host hooks (clear-recents confirm, stickers settings, …).
  final KeyboardPanelCallbacks callbacks;

  /// Trailing bottom-bar actions; defaults to [KeyboardPanelBottomActions.standard].
  final KeyboardPanelBottomActions? bottomActions;

  @override
  State<KeyboardPanel> createState() => _KeyboardPanelState();
}

class _KeyboardPanelState extends State<KeyboardPanel>
    with TickerProviderStateMixin {
  ChatBottomInsetController get _inset => widget.controller.inset;

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
  late List<KeyboardPanelTab> _tabs;
  late final ValueNotifier<int> _pageIndex;
  late final ValueNotifier<double> _page;
  late final ValueNotifier<bool> _pageDragging;

  // --- Search ---------------------------------------------------------------

  final TextEditingController _search = TextEditingController();
  final FocusNode _searchFocus = FocusNode(debugLabel: 'KeyboardPanelSearch');
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

  EmojiDataSource get _dataSource => widget.dataSource;

  Future<void>? _searchOpenOp;
  Future<void>? _searchCloseOp;

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
    _inset.addListener(_onController);
    _inset.heightListenable.addListener(_onInsetHeight);
    _bindPanelController(widget.controller);
    chatChromeLog(
      'KeyboardPanel initState isOpen=${widget.controller.isOpen} '
      'tabs=${_tabs.length}',
    );
  }

  @override
  void didUpdateWidget(KeyboardPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.allow != widget.allow) {
      _tabs = widget.allow.tabs;
      if (_pageIndex.value >= _tabs.length) _pageIndex.value = 0;
    }
    if (!identical(oldWidget.controller, widget.controller)) {
      _unbindPanelController(oldWidget.controller);
      oldWidget.controller.inset.removeListener(_onController);
      oldWidget.controller.inset.heightListenable.removeListener(
        _onInsetHeight,
      );
      _inset.addListener(_onController);
      _inset.heightListenable.addListener(_onInsetHeight);
      _bindPanelController(widget.controller);
    }
  }

  @override
  void dispose() {
    _unbindPanelController(widget.controller);
    _inset.removeListener(_onController);
    _inset.heightListenable.removeListener(_onInsetHeight);
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

  void _bindPanelController(KeyboardPanelController panel) {
    panel.bindProjection(
      onOpen: _projectOpen,
      onClose: _projectClose,
      onSearchOpen: _projectSearchOpen,
      onSearchClose: _projectSearchClose,
      onTab: _projectTab,
    );
    if (panel.isOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !identical(widget.controller, panel)) return;
        if (!panel.isOpen) return;
        _open(replacingKeyboard: panel.inset.openedReplacingIme);
        if (panel.isSearchOpen) {
          _openSearch();
        }
        _syncPagerToControllerTab(panel.selectedTab);
      });
    }
  }

  void _unbindPanelController(KeyboardPanelController panel) {
    panel.bindProjection();
  }

  void _projectOpen() {
    _open(replacingKeyboard: _inset.openedReplacingIme);
  }

  void _projectClose({required bool waitForIme}) {
    _close(notifyController: false, waitForIme: waitForIme);
  }

  Future<void> _projectSearchOpen() {
    final op = _openSearch();
    _searchOpenOp = op;
    return op.whenComplete(() {
      if (identical(_searchOpenOp, op)) {
        _searchOpenOp = null;
      }
    });
  }

  Future<void> _projectSearchClose({required bool hideKeyboard}) {
    final op = _closeSearch(hideKeyboard: hideKeyboard);
    _searchCloseOp = op;
    return op.whenComplete(() {
      if (identical(_searchCloseOp, op)) {
        _searchCloseOp = null;
      }
    });
  }

  void _projectTab(KeyboardPanelTab tab) {
    _syncPagerToControllerTab(tab);
  }

  void _syncPagerToControllerTab(KeyboardPanelTab tab) {
    final index = _tabs.indexOf(tab);
    if (index < 0) return;
    _commitPage(index, jump: true, fromController: true);
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
    final preferred = widget.controller.selectedTab;
    final idx = _tabs.indexOf(preferred);
    return idx >= 0 ? idx : 0;
  }

  // --- Inset controller / handoff -------------------------------------------

  void _onController() {
    if (_opening || _closing) return;
    _maybeDismissHandoffShell();
    if (_handoffToKeyboard) return;

    if (!_inset.isPanelOpen && (_visible || _progress.value > 0)) {
      chatChromeLog('KeyboardPanel controller cleared panel → sync close');
      widget.controller.adoptClose();
      unawaited(_close(notifyController: false));
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
    if (!_handoffToKeyboard || _inset.isHoldingForIme) return;
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

    final target = _closing ? _closeTarget : _inset.panelTarget;
    if (target <= 0 && !_closing) return;

    if (!_closing && !_inset.isPanelOpen) return;

    if (_closing) {
      // Inset stays ≥ 0 (target → 0). Safe-area exit is a local Transform.
      _inset.setPanelCloseOccupancy(_progress.value * _closeTarget);
    } else {
      _inset.setPanelOccupancy(_progress.value * target);
    }
  }

  // --- Open / close projection ----------------------------------------------

  /// Projects an open from [KeyboardPanelController] (or heals chrome).
  ///
  /// [replacingKeyboard]: skip entrance animation when IME was up (REPLACE).
  /// No-ops when tabs are empty or an open is already in flight. Commits
  /// deferred recents and rebinds the pager before the [PageView] mounts.
  /// Claims the inset only when the controller has not already claimed it
  /// (heal path — hosts MUST still [KeyboardPanelController.open] normally).
  Future<void> _open({bool replacingKeyboard = false}) async {
    chatChromeLog(
      'KeyboardPanel.open enter replacing=$replacingKeyboard '
      'visible=$_visible progress=${_progress.value} '
      'opening=$_opening closing=$_closing tabs=${_tabs.length} '
      'controllerOpen=${_inset.isPanelOpen} '
      'target=${_inset.panelTarget} '
      'published=${_inset.height}',
    );
    if (_tabs.isEmpty) {
      chatChromeLog('KeyboardPanel.open ABORT empty tabs');
      return;
    }
    if (_opening) {
      chatChromeLog('KeyboardPanel.open ABORT already opening');
      return;
    }

    final healChrome = _handoffToKeyboard || !_contentVisible;
    _restoreChromeForOpen();

    if (_visible && _progress.value >= 1 && _inset.isPanelOpen) {
      chatChromeLog(
        'KeyboardPanel.open ABORT already fully open heal=$healChrome',
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
    if (!_inset.isPanelOpen) {
      chatChromeLog('KeyboardPanel.open claiming slot (controller did not)');
      _inset.openPanel(landscape: landscape);
      _replacingKeyboard = _inset.openedReplacingIme;
    }
    widget.controller.adoptOpen();

    _layoutHeight = _inset.panelTarget + safeBottom;
    if (_layoutHeight < safeBottom + 96) {
      _layoutHeight =
          _inset.panelTargetHeight(landscape: landscape) + safeBottom;
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

    if (_replacingKeyboard) {
      chatChromeLog('KeyboardPanel.open REPLACE snap progress=1');
      _progress.value = 1;
      _inset.setPanelOccupancy(_inset.panelTarget);
      _opening = false;
      _ensurePageSyncedAfterOpen();
      // Warm after snap so REPLACE open does not pay first-fling glyph raster.
      _emojiPageKey.currentState?.warmAhead().ignore();
      return;
    }

    chatChromeLog('KeyboardPanel.open COLD animate 0→1');
    _progress.value = 0;
    _inset.setPanelOccupancy(0);
    // Layout the page, then warm glyphs without blocking the open animation.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || _closing) {
      _opening = false;
      return;
    }
    _emojiPageKey.currentState?.warmAhead().ignore();
    await Future<void>.delayed(KeyboardPanelMotion.startDelay);
    if (!mounted || _closing) {
      chatChromeLog(
        'KeyboardPanel.open COLD aborted after delay '
        'mounted=$mounted closing=$_closing',
      );
      _opening = false;
      return;
    }
    try {
      await _progress.animateTo(1, curve: KeyboardPanelMotion.curve);
      chatChromeLog(
        'KeyboardPanel.open COLD done progress=${_progress.value} '
        'published=${_inset.height}',
      );
    } catch (e, st) {
      chatChromeLog('KeyboardPanel.open COLD animate error $e\n$st');
    } finally {
      _opening = false;
      _ensurePageSyncedAfterOpen();
    }
  }

  /// Projects a close from [KeyboardPanelController] (or heals chrome).
  ///
  /// [waitForIme]: keyboard handoff — hide emoji chrome, keep shell + inset
  /// hold until IME takes over. [notifyController]: when `true`, releases the
  /// inset via [ChatBottomInsetController.closePanel] and adopts closed SoT on
  /// [KeyboardPanelController]; when `false` (controller-driven projection),
  /// cold close finishes with [KeyboardPanelController.completeColdClose].
  Future<void> _close({
    bool notifyController = true,
    bool waitForIme = false,
  }) async {
    chatChromeLog(
      'KeyboardPanel.close waitForIme=$waitForIme notify=$notifyController '
      'progress=${_progress.value} published=${_inset.height}',
    );
    if (_closing) return;

    if (_handoffToKeyboard) {
      if (waitForIme) {
        chatChromeLog('KeyboardPanel.close handoff duplicate → finish shell');
        if (_inset.isHoldingForIme) {
          _inset.closePanel(waitForIme: false);
        }
        if (notifyController) {
          widget.controller.adoptClose();
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
    if (notifyController) {
      widget.controller.adoptClose();
    }

    // Search cannot outlive a closed panel — clear local chrome (SoT already
    // cleared when the host used [KeyboardPanelController.close]).
    if (_searchOpen.value) {
      _searchOpen.value = false;
      _search.clear();
      _searchFocus.unfocus();
    }

    if (waitForIme) {
      // Keyboard handoff: hide emoji chrome, keep panel shell + inset hold.
      _handoffToKeyboard = true;
      _contentVisible = false;
      if (notifyController) {
        _inset.closePanel(waitForIme: true);
      }
      if (mounted) {
        setState(() {});
      }
      chatChromeLog(
        'KeyboardPanel.close handoff shell-only progress=${_progress.value}',
      );
      return;
    }

    _closing = true;
    // Cold dismiss: animate occupancy target → −safeBottom, then release.
    _closeSafeBottom = MediaQuery.viewPaddingOf(context).bottom;
    _closeTarget = _inset.isPanelOpen
        ? (_inset.panelTarget > 0
              ? _inset.panelTarget
              : math.max(0.0, _inset.height))
        : math.max(0.0, _inset.height);
    if (_closeTarget <= 0) {
      _closeTarget = _inset.panelTargetHeight(
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
        'KeyboardPanel.close COLD done progress=${_progress.value} '
        'published=${_inset.height}',
      );
    } catch (e, st) {
      chatChromeLog('KeyboardPanel.close animate error $e\n$st');
    }

    if (notifyController) {
      _inset.closePanel(waitForIme: false);
    } else {
      widget.controller.completeColdClose();
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
      _inset.collapsePanelFromSearch();
    });
    chatChromeLog('KeyboardPanel.close done published=${_inset.height}');
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
    final offset = KeyboardPanelBottomBar.scrollToggleOffset;

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
    if (_searchFocus.hasFocus && !widget.controller.isSearchOpen) {
      widget.controller.openSearch();
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
      _inset.panelBaseTarget,
      size.height - safeTop - safeBottom - composerBand - slack,
    );
  }

  /// Projects search expand. SoT is already committed when invoked via
  /// [KeyboardPanelController.openSearch]. If local chrome runs while SoT is
  /// still closed, adopts open without projecting again.
  Future<void> _openSearch() async {
    if (_searchOpen.value) {
      if (!_searchFocus.hasFocus) {
        _searchFocus.requestFocus();
      }
      return;
    }
    if (!widget.controller.isSearchOpen) {
      widget.controller.adoptSearch(true);
    }
    _searchOpen.value = true;
    _showBottomTab(false);
    _searchFieldTy.value = 0;
    if (mounted) setState(() {});

    final from = _inset.panelTarget;
    final avail = _availableMaxForSearch();
    final to = _inset.expandPanelForSearch(availableMax: avail);
    await _animateSearchHeight(from: from, to: to);

    if (!mounted) return;
    if (!_searchFocus.hasFocus) {
      _searchFocus.requestFocus();
    }
  }

  /// Projects search collapse. SoT is already committed when invoked via
  /// [KeyboardPanelController.closeSearch].
  ///
  /// Silent early return when local search is already closed and the inset is
  /// not search-expanded. [hideKeyboard] controls unfocus and
  /// [KeyboardPanelCallbacks.onSearchClosed]. Adopts closed SoT when local close
  /// runs while the controller still reports search open.
  Future<void> _closeSearch({bool hideKeyboard = true}) async {
    if (!_searchOpen.value && !_inset.isSearchExpanded) {
      return;
    }
    if (widget.controller.isSearchOpen) {
      widget.controller.adoptSearch(false);
    }
    if (hideKeyboard) {
      _searchFocus.unfocus();
    }
    _searchOpen.value = false;
    _search.clear();
    _deferredRecents.commit(_dataSource);

    final from = _inset.panelTarget;
    final to = _inset.panelBaseTarget;
    await _animateSearchHeight(from: from, to: to);
    _inset.collapsePanelFromSearch();

    if (!mounted) return;
    _showBottomTab(true);
    setState(() {});
    if (hideKeyboard) {
      // Stay on keyboard panel — host restores composer focus (IME stays down).
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
      _inset.setPanelOccupancy(to);
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
      _inset.setPanelOccupancy(h);
      _layoutHeight = h + safeBottom;
      if (mounted) setState(() {});
    }

    curved.addListener(tick);
    try {
      await controller.forward();
      _inset.setPanelOccupancy(to);
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
  ///
  /// When [fromController] is true, [KeyboardPanelController.selectTab] already
  /// committed SoT and prefs — this only projects the pager. Otherwise adopts
  /// SoT and persists (swipe / local reselect side paths).
  Future<void> _commitPage(
    int index, {
    required bool jump,
    bool fromController = false,
  }) async {
    if (index < 0 || index >= _tabs.length) return;

    final changed = index != _pageIndex.value;
    if (!changed && jump && _tabs[index] == KeyboardPanelTab.emoji) {
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
    if (_tabs[index] == KeyboardPanelTab.emoji) {
      _syncCatalogScrollBinding();
    }
    final tab = _tabs[index];
    if (changed) {
      if (!fromController) {
        widget.controller.adoptTab(tab);
        await widget.controller.store.setSelectedPage(tab.prefsPage);
      }
    }
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
        : _inset.panelTarget + safeBottom;

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
                              KeyboardPanelTab.emoji => EmojiPage(
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
                                  unawaited(widget.controller.openSearch());
                                },
                                onEmojiSelected: _onEmoji,
                                onClearRecents: _onRequestClearRecents,
                              ),
                              KeyboardPanelTab.gifs => const GifPageStub(),
                              KeyboardPanelTab.stickers =>
                                const StickerPageStub(),
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
                          child: KeyboardPanelNavBarFade(
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
                                      : KeyboardPanelBottomBar.hideSlide +
                                            safeBottom,
                                ),
                                duration:
                                    KeyboardPanelBottomBar.visibilityDuration,
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
                                  return KeyboardPanelBottomBar(
                                    tabs: _tabs,
                                    page: _page.value,
                                    selectedTab: _tabs[_pageIndex.value],
                                    pageDragging: _pageDragging.value,
                                    labels: widget.labels,
                                    actions:
                                        widget.bottomActions ??
                                        KeyboardPanelBottomActions.standard(
                                          onBackspace: widget.onBackspace,
                                          onStickerSettings: widget
                                              .callbacks
                                              .onStickerSettings,
                                        ),
                                    onSelectTab: (i) {
                                      // Jump type tab without pager smooth
                                      // scroll — indicator settles separately.
                                      _markBottomTabAfterClick();
                                      _pageDragging.value = false;
                                      final tab = _tabs[i];
                                      if (tab ==
                                          widget.controller.selectedTab) {
                                        // Same-value selectTab is silent — still
                                        // run reselect side effects (emoji → top).
                                        _commitPage(i, jump: true);
                                      } else {
                                        widget.controller.selectTab(tab);
                                      }
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
/// Hosts typically wire this to [KeyboardPanel.onBackspace] /
/// [KeyboardPanelBottomActions]. No-ops when the field is empty or the caret
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
