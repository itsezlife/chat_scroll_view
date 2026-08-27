import 'dart:async';

import 'package:chat_chrome/src/inset/chat_bottom_inset_controller.dart';
import 'package:chat_chrome/src/inset/keyboard_panel_store.dart';
import 'package:chat_chrome/src/panel/keyboard_panel_allow.dart';
import 'package:flutter/foundation.dart';

/// Host-owned chrome source of truth for the keyboard-replacement panel.
///
/// Owns desired open / search / type-tab state and the commands that claim or
/// release the bottom inset slot. Commands commit and notify typed listeners
/// even when no panel widget is bound; a mounted panel **projects** that state
/// into cold open, replace-IME, wait-for-IME handoff, search expand/collapse,
/// and type-tab pager chrome.
///
/// ## Ownership
///
/// **Owns:** desired [isOpen], [isSearchOpen], [selectedTab]; [open] / [close]
/// / [openSearch] / [closeSearch] / [selectTab] / [handleBack]; typed listeners
/// for each channel; driving [ChatBottomInsetController.openPanel] /
/// [closePanel] so the host does not dual-call inset claim plus panel open;
/// persisting [selectedTab] via [KeyboardPanelStore.setSelectedPage].
///
/// **Does not own:** inset occupancy math or IME live height (those stay on
/// [ChatBottomInsetController]), composer text, insert/backspace, clear-recents
/// UI, search-field text/focus widgets, or catalog extent scroll (page-local
/// `PanelCatalogController`). Soft-IME dismiss-before-search-exit is
/// **host-owned** (needs [BuildContext] / text-input channels); [handleBack]
/// only orders search then panel.
///
/// ## Listeners
///
/// [addOpenListener] / [removeOpenListener] — payload is the new [isOpen].
/// [addSearchListener] / [removeSearchListener] — payload is the new
/// [isSearchOpen]. [addTabListener] / [removeTabListener] — payload is the new
/// [selectedTab]. Same callback twice is a no-op (dedup-on-add). Dispatch
/// iterates a snapshot so listeners MAY add/remove during notify without
/// concurrent modification.
///
/// ## Silent paths
///
/// Same-value [open] / [close] / [openSearch] / [closeSearch] / [selectTab]
/// (desired state already matches) do not notify. After [dispose], mutating
/// entry points and listener registration are silent no-ops; [isDisposed] is
/// `true`.
///
/// ## Panel projection
///
/// The bound panel registers open/close/search/tab projection handlers.
/// [open] claims the inset then asks the panel to run entrance motion
/// (REPLACE vs COLD from [ChatBottomInsetController.openedReplacingIme]).
/// [close] with `waitForIme: true` releases the slot with an IME hold
/// immediately; cold [close] defers [ChatBottomInsetController.closePanel]
/// until the panel finishes occupancy animation via [completeColdClose]. When
/// unbound, cold [close] releases the inset immediately so SoT does not leave
/// a claimed slot. [openSearch] / [closeSearch] / [selectTab] project when
/// bound; [adoptOpen] / [adoptClose] / [adoptSearch] / [adoptTab] sync SoT
/// when the panel changed chrome without going through host commands.
///
/// The panel MUST NOT dispose this controller. Host owns lifetime.
final class KeyboardPanelController {
  /// Creates a chrome SoT backed by [inset] and [store].
  ///
  /// [inset] is the single bottom-slot arbiter; [store] supplies persisted
  /// panel height and selected-tab prefs. [selectedTab] seeds from
  /// [KeyboardPanelStore.selectedPage] (host SHOULD [KeyboardPanelStore.load]
  /// first). Disposing this controller does not dispose [inset] or [store].
  KeyboardPanelController({
    required ChatBottomInsetController inset,
    required KeyboardPanelStore store,
  }) : _inset = inset,
       _store = store,
       _selectedTab = KeyboardPanelTabPrefs.fromPrefs(store.selectedPage);

  final ChatBottomInsetController _inset;
  final KeyboardPanelStore _store;

  var _isOpen = false;
  var _isSearchOpen = false;
  KeyboardPanelTab _selectedTab;
  var _disposed = false;

  /// Pending cold-close: inset still claimed until [completeColdClose].
  var _coldClosePending = false;

  VoidCallback? _projectOpen;
  void Function({required bool waitForIme})? _projectClose;
  Future<void> Function()? _projectSearchOpen;
  Future<void> Function({required bool hideKeyboard})? _projectSearchClose;
  ValueChanged<KeyboardPanelTab>? _projectTab;

  final _openListeners = <ValueChanged<bool>>[];
  final _searchListeners = <ValueChanged<bool>>[];
  final _tabListeners = <ValueChanged<KeyboardPanelTab>>[];

  /// Bottom-inset arbiter passed at construction.
  ChatBottomInsetController get inset => _inset;

  /// Keyboard-height / tab prefs store passed at construction.
  KeyboardPanelStore get store => _store;

  /// Desired open state — committed by [open] / [close] even when unbound.
  bool get isOpen => _isOpen;

  /// Desired search-expanded state — committed by [openSearch] / [closeSearch]
  /// even when unbound.
  bool get isSearchOpen => _isSearchOpen;

  /// Desired type tab — seeded from [store] and committed by [selectTab].
  KeyboardPanelTab get selectedTab => _selectedTab;

  /// Whether [dispose] has been called.
  bool get isDisposed => _disposed;

  // --- Open listeners -------------------------------------------------------

  /// Subscribe to open/close commits. Callback receives the new [isOpen].
  ///
  /// Adding the same callback twice is a no-op. Unknown removals are no-ops.
  void addOpenListener(ValueChanged<bool> callback) {
    if (_disposed) return;
    if (_openListeners.contains(callback)) return;
    _openListeners.add(callback);
  }

  /// Unsubscribe from [addOpenListener]. Unknown [callback] is a no-op.
  void removeOpenListener(ValueChanged<bool> callback) =>
      _openListeners.remove(callback);

  void _emitOpen(bool open) {
    if (_disposed) return;
    for (final cb in List<ValueChanged<bool>>.of(
      _openListeners,
      growable: false,
    )) {
      cb(open);
    }
  }

  // --- Search listeners -----------------------------------------------------

  /// Subscribe to search open/close commits. Payload is the new [isSearchOpen].
  ///
  /// Adding the same callback twice is a no-op. Unknown removals are no-ops.
  void addSearchListener(ValueChanged<bool> callback) {
    if (_disposed) return;
    if (_searchListeners.contains(callback)) return;
    _searchListeners.add(callback);
  }

  /// Unsubscribe from [addSearchListener]. Unknown [callback] is a no-op.
  void removeSearchListener(ValueChanged<bool> callback) =>
      _searchListeners.remove(callback);

  void _emitSearch(bool open) {
    if (_disposed) return;
    for (final cb in List<ValueChanged<bool>>.of(
      _searchListeners,
      growable: false,
    )) {
      cb(open);
    }
  }

  // --- Tab listeners --------------------------------------------------------

  /// Subscribe to type-tab commits. Callback receives the new [selectedTab].
  ///
  /// Adding the same callback twice is a no-op. Unknown removals are no-ops.
  void addTabListener(ValueChanged<KeyboardPanelTab> callback) {
    if (_disposed) return;
    if (_tabListeners.contains(callback)) return;
    _tabListeners.add(callback);
  }

  /// Unsubscribe from [addTabListener]. Unknown [callback] is a no-op.
  void removeTabListener(ValueChanged<KeyboardPanelTab> callback) =>
      _tabListeners.remove(callback);

  void _emitTab(KeyboardPanelTab tab) {
    if (_disposed) return;
    for (final cb in List<ValueChanged<KeyboardPanelTab>>.of(
      _tabListeners,
      growable: false,
    )) {
      cb(tab);
    }
  }

  // --- Commands -------------------------------------------------------------

  /// Opens the panel: claims the inset slot and commits [isOpen] to `true`.
  ///
  /// Notifies open listeners and projects entrance motion when a panel is
  /// bound. [landscape] selects the height prefs orientation for
  /// [ChatBottomInsetController.openPanel]. Same-value and post-dispose calls
  /// are silent no-ops.
  ///
  /// Host MUST NOT also call [ChatBottomInsetController.openPanel] — this
  /// method is the sole claim path.
  void open({required bool landscape}) {
    if (_disposed) return;
    if (_isOpen) return;

    _coldClosePending = false;
    _isOpen = true;
    _inset.openPanel(landscape: landscape);
    _emitOpen(true);
    _projectOpen?.call();
  }

  /// Closes the panel: commits [isOpen] to `false` and releases or holds inset.
  ///
  /// Also clears [isSearchOpen] (search cannot outlive a closed panel) and
  /// notifies search listeners when search was open.
  ///
  /// [waitForIme]: keyboard handoff — projects shell-only hide, then calls
  /// [ChatBottomInsetController.closePanel] with hold. Cold close
  /// (`waitForIme: false`) projects occupancy animation; the bound panel MUST
  /// call [completeColdClose] when done. When unbound, cold close releases the
  /// inset immediately.
  ///
  /// When already closed, a further [waitForIme] close still projects so a
  /// stuck handoff shell can finish; cold same-value and post-dispose calls
  /// are silent no-ops.
  void close({bool waitForIme = false}) {
    if (_disposed) return;
    if (!_isOpen) {
      if (waitForIme) {
        _projectClose?.call(waitForIme: true);
      }
      return;
    }

    _isOpen = false;
    _emitOpen(false);
    _clearSearchOnPanelClose();

    if (waitForIme) {
      _coldClosePending = false;
      // Project before releasing inset so the panel sets handoff flags before
      // [ChatBottomInsetController] notifies — otherwise the inset listener
      // starts a cold close and races the wait-for-IME path.
      _projectClose?.call(waitForIme: true);
      _inset.closePanel(waitForIme: true);
      return;
    }

    if (_projectClose case final project?) {
      _coldClosePending = true;
      project(waitForIme: false);
      return;
    }

    _coldClosePending = false;
    _inset.closePanel(waitForIme: false);
  }

  /// Opens search chrome: commits [isSearchOpen] to `true` and projects expand.
  ///
  /// Completes when the bound panel finishes expand motion (or immediately when
  /// unbound). Same-value and post-dispose are silent completed futures. Does
  /// not open the panel; hosts that need both MUST [open] first.
  Future<void> openSearch() async {
    if (_disposed) return;
    if (_isSearchOpen) return;

    _isSearchOpen = true;
    _emitSearch(true);
    final project = _projectSearchOpen;
    if (project == null) return;
    await project();
  }

  /// Closes search chrome: commits [isSearchOpen] to `false` and projects
  /// collapse.
  ///
  /// Completes when the bound panel finishes collapse motion (or immediately
  /// when unbound). Hosts that hand off to the IME MUST await this before
  /// [close] with `waitForIme: true` so the hold captures the keyboard-sized
  /// base, not the search-expanded height.
  ///
  /// [hideKeyboard]: when `false`, projection leaves soft-IME focus transfer
  /// to the host (composer tap) so the keyboard does not flicker. Same-value
  /// and post-dispose are silent completed futures.
  Future<void> closeSearch({bool hideKeyboard = true}) async {
    if (_disposed) return;
    if (!_isSearchOpen) return;

    _isSearchOpen = false;
    _emitSearch(false);
    final project = _projectSearchClose;
    if (project == null) return;
    await project(hideKeyboard: hideKeyboard);
  }

  /// System-back ordering: search first, then panel.
  ///
  /// Returns `true` when this call consumed the back (closed search while the
  /// panel stayed open, or closed the panel). Returns `false` when neither
  /// search nor panel is open, or after dispose. Soft-IME dismiss-before-
  /// search-exit is **host-owned** — the host MUST hide the IME first when
  /// search focus still owns the keyboard, then call this method.
  bool handleBack() {
    if (_disposed) return false;
    if (_isSearchOpen) {
      closeSearch();
      return true;
    }
    if (_isOpen) {
      close();
      return true;
    }
    return false;
  }

  /// Selects a type tab: commits [selectedTab], persists prefs, notifies, and
  /// projects the pager when bound.
  ///
  /// Same-value and post-dispose are silent no-ops. Persistence uses
  /// [KeyboardPanelTab.prefsPage] on [KeyboardPanelStore.setSelectedPage].
  void selectTab(KeyboardPanelTab tab) {
    if (_disposed) return;
    if (_selectedTab == tab) return;

    _selectedTab = tab;
    unawaited(_store.setSelectedPage(tab.prefsPage));
    _emitTab(tab);
    _projectTab?.call(tab);
  }

  /// Panel-only: finishes a cold [close] by releasing the inset slot.
  ///
  /// Silent no-op when not pending, already open again, or disposed. Hosts
  /// MUST NOT call this — use [close].
  void completeColdClose() {
    if (_disposed) return;
    if (!_coldClosePending) return;
    if (_isOpen) {
      _coldClosePending = false;
      return;
    }
    _coldClosePending = false;
    if (_inset.isPanelOpen) {
      _inset.closePanel(waitForIme: false);
    }
  }

  /// Panel-only: adopts open SoT when the panel opened without [open].
  ///
  /// Same-value and post-dispose are silent no-ops. Does not claim inset or
  /// project — the panel already did. Hosts MUST NOT call this.
  void adoptOpen() {
    if (_disposed) return;
    if (_isOpen) return;
    _coldClosePending = false;
    _isOpen = true;
    _emitOpen(true);
  }

  /// Panel-only: adopts closed SoT when the panel closed without [close].
  ///
  /// Same-value and post-dispose are silent no-ops. Does not release inset or
  /// project — the panel already did. Clears [isSearchOpen] when search was
  /// open. Hosts MUST NOT call this.
  void adoptClose() {
    if (_disposed) return;
    if (!_isOpen) return;
    _coldClosePending = false;
    _isOpen = false;
    _emitOpen(false);
    _clearSearchOnPanelClose();
  }

  /// Panel-only: adopts search SoT when the panel opened/closed search without
  /// [openSearch] / [closeSearch].
  ///
  /// Same-value and post-dispose are silent no-ops. Does not project. Hosts
  /// MUST NOT call this.
  void adoptSearch(bool open) {
    if (_disposed) return;
    if (_isSearchOpen == open) return;
    _isSearchOpen = open;
    _emitSearch(open);
  }

  /// Panel-only: adopts type-tab SoT when the pager changed without [selectTab].
  ///
  /// Same-value and post-dispose are silent no-ops. Does not project or write
  /// prefs — the panel already persisted. Hosts MUST NOT call this.
  void adoptTab(KeyboardPanelTab tab) {
    if (_disposed) return;
    if (_selectedTab == tab) return;
    _selectedTab = tab;
    _emitTab(tab);
  }

  void _clearSearchOnPanelClose() {
    if (!_isSearchOpen) return;
    _isSearchOpen = false;
    _emitSearch(false);
  }

  // --- Panel bind -----------------------------------------------------------

  /// Registers projection handlers for the mounted panel.
  ///
  /// Panel-only. Pass `null` handlers on detach. Does not dispose this
  /// controller. When binding while [isOpen] is already `true`, the panel
  /// SHOULD project an immediate open (REPLACE vs COLD from inset state).
  /// When binding while [isSearchOpen] / [selectedTab] already differ from
  /// the panel's local chrome, the panel SHOULD project those as well.
  void bindProjection({
    VoidCallback? onOpen,
    void Function({required bool waitForIme})? onClose,
    Future<void> Function()? onSearchOpen,
    Future<void> Function({required bool hideKeyboard})? onSearchClose,
    ValueChanged<KeyboardPanelTab>? onTab,
  }) {
    if (_disposed) return;
    _projectOpen = onOpen;
    _projectClose = onClose;
    _projectSearchOpen = onSearchOpen;
    _projectSearchClose = onSearchClose;
    _projectTab = onTab;
  }

  // --- Lifecycle ------------------------------------------------------------

  /// Drops listeners and projection binds; marks disposed. Idempotent.
  ///
  /// After dispose, mutating commands, [bindProjection], and listener adds are
  /// silent no-ops. Does not dispose [inset] or [store].
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _coldClosePending = false;
    _projectOpen = null;
    _projectClose = null;
    _projectSearchOpen = null;
    _projectSearchClose = null;
    _projectTab = null;
    _openListeners.clear();
    _searchListeners.clear();
    _tabListeners.clear();
  }
}
