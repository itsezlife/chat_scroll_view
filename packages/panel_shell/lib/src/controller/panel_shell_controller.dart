import 'dart:async';

import 'package:chrome_foundation/chrome_foundation.dart' show ChromeHintTiming;
import 'package:content_model/content_model.dart';
import 'package:listen/listen.dart';
import 'package:panel_shell/src/controller/event_publisher.dart';
import 'package:panel_shell/src/controller/panel_search_state.dart';
import 'package:panel_shell/src/diagnostics/panel_shell_op.dart';
import 'package:panel_shell/src/event/panel_event.dart';
import 'package:panel_shell/src/page/page_availability.dart';
import 'package:panel_shell/src/page/page_controller_registry.dart';
import 'package:panel_shell/src/page/panel_page.dart';
import 'package:panel_shell/src/page/panel_page_host.dart';
import 'package:panel_shell/src/scroll/page_scroll_activity.dart';

/// The single source of truth for which page is selected and what the search
/// state is; the read side is a set of [ValueListenable]s and event streams, the write side a set of
/// one-way intents.
///
/// ## Ownership
///
/// **Owns:** the selected page id, the [PanelSearchState] (open, query, focus
/// intent), the per-page controller registry, the publication of
/// [PanelEvent]s, the **presence** (visible, opening) a presentation
/// reports so a host can wire the pause signals of work that must not run
/// while the panel is hidden or moving, and the **fresh open** signal a
/// presentation sends its pages ([reportFreshOpen]).
///
/// It also keeps each page's **availability** ([PageAvailability]), which
/// the host sets ([setPageAvailability]) and the controller never decides.
/// The panel leaves a page that cannot be selected (dimmed or hidden) for
/// the first selectable page shown, and publishes an attempt on a dimmed
/// page as [PageDenied], at most once per [deniedRepeatWindow].
///
/// **Does not own:** whether the panel is open on screen, its height, the
/// soft keyboard or any inset; those belong to a presentation controller that
/// wraps this one. Nor the content of a page, nor recents.
///
/// ## Intents
///
/// [selectPage], [openSearch], [closeSearch], [setQuery], [invokeAction],
/// [requestSearchFocus], [releaseSearchFocus] and [handleBack] are the only
/// ways to change the state, and widgets use the same ones a host does: a tab
/// tap, a swipe and a host call all arrive at [selectPage]. There is no
/// back-door that lets a widget overwrite state the controller did not
/// decide. Intents that change nothing are silent, and after [dispose] every
/// intent is a no-op.
///
/// ## Persistence
///
/// The selected page id is written to the [PreferenceStore] as a string and
/// read back at construction; a remembered id that is no longer registered
/// falls back to the first page, and one that cannot be selected to the
/// first selectable page. A move the controller makes because a page stopped
/// being available is not persisted: the user's choice holds for when the
/// page comes back. A failure to persist is reported to the zone and leaves
/// the in-memory selection as it is.
final class PanelShellController {
  /// Creates a controller over [pages], in tab order.
  ///
  /// [preferences] is already loaded, so the remembered page is known
  /// synchronously. [controllers] lets a test or host supply the registry;
  /// when omitted the controller creates one and disposes it. A supplied
  /// registry is left to its owner. Each page starts at its registered
  /// [PanelPage.availability].
  ///
  /// Throws an [ArgumentError] for an empty [pages] or a repeated page id.
  factory PanelShellController({
    required List<PanelPage> pages,
    required PreferenceStore preferences,
    PageControllerRegistry? controllers,
    Duration deniedRepeatWindow = defaultDeniedRepeatWindow,
  }) {
    final owned = switch (controllers) {
      null => PanelPageControllers(),
      _ => null,
    };
    return PanelShellController._(
      pages,
      preferences,
      controllers ?? owned!,
      owned,
      deniedRepeatWindow,
    );
  }

  PanelShellController._(
    List<PanelPage> pages,
    PreferenceStore preferences,
    this.controllers,
    this._ownedControllers,
    this.deniedRepeatWindow,
  ) : pages = List.unmodifiable(pages),
      _preferences = preferences {
    if (pages.isEmpty) {
      throw ArgumentError.value(pages, 'pages', 'must not be empty');
    }
    for (final page in pages) {
      if (_byId.containsKey(page.id)) {
        throw ArgumentError.value(page.id, 'pages', 'page id repeated');
      }
      _byId[page.id] = page;
    }
    final availability = Map<String, PageAvailability>.unmodifiable({
      for (final page in pages) page.id: page.availability,
    });
    _availability = ValueNotifier(availability);
    _shown = ValueNotifier(_shownOf(availability));
    final remembered = preferences.selectedPageId;
    final wanted = remembered != null && _byId.containsKey(remembered)
        ? remembered
        : pages.first.id;
    _selected = ValueNotifier<String>(
      availability[wanted]!.isSelectable ? wanted : _fallback() ?? wanted,
    );
  }

  /// The stock [deniedRepeatWindow]: as long as the hint at the tab stays
  /// up.
  static const Duration defaultDeniedRepeatWindow = ChromeHintTiming.tabHint;

  /// How long after a published [PageDenied] another attempt on the same
  /// page is ignored, so a burst of taps on a dimmed tab shows its hint once.
  final Duration deniedRepeatWindow;

  /// The registered pages, in tab order. Unmodifiable.
  final List<PanelPage> pages;

  /// Where pages keep controllers that must outlive their widgets, so a
  /// presentation switch restores scroll offsets and loaded collections.
  final PageControllerRegistry controllers;

  final PreferenceStore _preferences;
  final PanelPageControllers? _ownedControllers;
  final _byId = <String, PanelPage>{};
  late final ValueNotifier<String> _selected;
  final _search = ValueNotifier<PanelSearchState>(PanelSearchState.closed);
  final _searchBusy = ValueNotifier<bool>(false);
  final _visible = ValueNotifier<bool>(false);
  final _opening = ValueNotifier<bool>(false);
  final _freshOpen = _Signal();
  final _events = EventPublisher<PanelEvent>();
  final _scrollActivity = EventPublisher<PageScrollActivity>();
  final _searchResultCounts = EventPublisher<int>();
  final _bottomExtent = ValueNotifier<double>(0);
  final _autoHideHolds = ValueNotifier<int>(0);
  final _bottomExtents = <String, double>{};
  final _hosts = <String, _PageHost>{};
  late final ValueNotifier<Map<String, PageAvailability>> _availability;
  late final ValueNotifier<List<PanelPage>> _shown;
  final _availabilityOf = <String, _AvailabilityOf>{};
  final _deniedGuards = <String, Timer>{};
  var _disposed = false;

  /// The id of the selected page.
  ValueListenable<String> get selectedPageId => _selected;

  /// The selected page.
  PanelPage get selectedPage => _byId[_selected.value]!;

  /// What the selected page offers around it now: its declared
  /// [PanelPage.capabilities] while it is available, none otherwise (its
  /// content replaced by a text).
  PageCapabilities get selectedCapabilities => _capabilitiesOf(selectedPage);

  /// The availability of every registered page, by id. Unmodifiable; a new
  /// map on each change.
  ValueListenable<Map<String, PageAvailability>> get availability =>
      _availability;

  /// The pages that have a tab and a place in the pager: the registered ones
  /// in tab order, less the hidden. Never empty: with every page hidden the
  /// first stays, since a panel always shows one.
  ValueListenable<List<PanelPage>> get shownPages => _shown;

  /// The search state: open, query and focus intent in one snapshot.
  ValueListenable<PanelSearchState> get search => _search;

  /// Whether a search for the current query is in flight, as the selected
  /// page reported it.
  ValueListenable<bool> get searchBusy => _searchBusy;

  /// The outward effects of the panel: the one stream a host handles.
  Stream<PanelEvent> get events => _events.stream;

  /// What the selected page's scroll is doing; the bottom bar listens.
  Stream<PageScrollActivity> get scrollActivity => _scrollActivity.stream;

  /// Result counts the selected page reported for settled searches.
  Stream<int> get searchResultCounts => _searchResultCounts.stream;

  /// How tall the strip the selected page pins at the bottom of its own box
  /// is, as the page reported it; 0 for none.
  ///
  /// The floating bar of the pointer arrangement rises by it.
  ValueListenable<double> get bottomExtent => _bottomExtent;

  /// How many holds on auto-hide the pages keep now
  /// ([PanelPageHost.holdAutoHide]), from every page.
  ///
  /// The host listens and keeps its presentation open while it is above zero.
  ValueListenable<int> get autoHideHolds => _autoHideHolds;

  /// **Panel visible**: whether a presentation shows the panel on screen,
  /// including while it slides in or out. The pause signal of work that is
  /// pointless when nothing is seen.
  ValueListenable<bool> get visible => _visible;

  /// **Panel opening**: whether the panel is moving in or out. The pause
  /// signal of work that would drop frames during the motion.
  ValueListenable<bool> get opening => _opening;

  /// **Fresh open**: signals each time a presentation opens the panel afresh,
  /// asking every page to come back as a new open shows it
  /// ([reportFreshOpen]). The same signal every host's
  /// [PanelPageHost.freshOpen] is.
  Listenable get freshOpen => _freshOpen;

  /// Whether [dispose] has been called.
  bool get isDisposed => _disposed;

  /// The connection page [pageId] builds against.
  ///
  /// The same host is returned for the same id. Throws an [ArgumentError] for
  /// an id that is not registered.
  PanelPageHost hostFor(String pageId) {
    final page = _byId[pageId];
    if (page == null) {
      throw ArgumentError.value(pageId, 'pageId', 'not a registered page');
    }
    return _hosts.putIfAbsent(pageId, () => _PageHost(this, page));
  }

  /// The availability of page [pageId], signalling only when it changes, so
  /// that page's content rebuilds and no other page's does.
  ///
  /// The same listenable is returned for the same id. Throws an
  /// [ArgumentError] for an id that is not registered.
  ValueListenable<PageAvailability> availabilityOf(String pageId) {
    if (!_byId.containsKey(pageId)) {
      throw ArgumentError.value(pageId, 'pageId', 'not a registered page');
    }
    return _availabilityOf.putIfAbsent(
      pageId,
      () => _AvailabilityOf(_availability, pageId),
    );
  }

  // --- Intents --------------------------------------------------------------

  /// Selects the page [pageId].
  ///
  /// Persists the id, closes search if the new page declares none, and
  /// publishes [PageChanged]. Selecting the page that is already selected
  /// changes nothing but signals that page's `reselected`. An id that is not
  /// registered is ignored.
  ///
  /// A page that cannot be selected is refused: a hidden one silently, a
  /// dimmed one by publishing [PageDenied] (a tap on its tab, a swipe onto
  /// it, a shortcut), unless one was published for it within
  /// [deniedRepeatWindow].
  void selectPage(String pageId) {
    if (_disposed) return;
    final page = _byId[pageId];
    if (page == null) return;
    switch (_availability.value[pageId]!) {
      case PageAvailability$Dimmed():
        _reportDenied(pageId);
        return;
      case PageAvailability$Hidden():
        return;
      case PageAvailability$Available() || PageAvailability$Replaced():
        break;
    }
    if (pageId == _selected.value) {
      _hosts[pageId]?._reselect();
      return;
    }
    _moveTo(page);
    unawaited(_persist(pageId));
  }

  /// Sets the availability of page [pageId], as the host decides it; the
  /// panel follows within this call, and only that page's content rebuilds.
  ///
  /// When the selected page can no longer be selected, the panel moves to
  /// the first selectable page shown and publishes [PageChanged] (the move
  /// is not persisted); when its content stops being available, an open
  /// search closes. Emits `capabilities / pageAvailability` (debug) under
  /// [correlation], with the page id and the form, never its text. A value
  /// equal to the current one, an id that is not registered and any call
  /// after [dispose] change nothing.
  void setPageAvailability(
    String pageId,
    PageAvailability availability, {
    ChatCorrelation correlation = ChatCorrelation.none,
  }) {
    if (_disposed) return;
    final current = _availability.value[pageId];
    if (current == null || current == availability) return;
    final next = Map<String, PageAvailability>.unmodifiable({
      ..._availability.value,
      pageId: availability,
    });
    _availability.value = next;
    final shown = _shownOf(next);
    if (!_sameIds(shown, _shown.value)) _shown.value = shown;
    if (availability is! PageAvailability$Dimmed) {
      _deniedGuards.remove(pageId)?.cancel();
    }
    String? movedTo;
    if (pageId == _selected.value) {
      if (!availability.isSelectable) {
        if (_fallback() case final fallback?) {
          _moveTo(_byId[fallback]!);
          movedTo = fallback;
        }
      } else if (_search.value.isOpen && !selectedCapabilities.search) {
        closeSearch();
      }
    }
    ChatDiagnostics.current.emit(
      ChatEventLevel.debug,
      ChatEventCategory.capabilities,
      PanelShellOp.pageAvailability,
      correlation: correlation,
      fields: () => {
        'page': pageId,
        'form': availability.diagnosticForm,
        'movedTo': ?movedTo,
      },
    );
  }

  /// Opens search mode above the selected page.
  ///
  /// Does nothing when the selected page does not declare search. With
  /// [focus] the field is asked to take focus; calling again on an open
  /// search with [focus] only adds the focus intent. Publishes [SearchOpened]
  /// when it opened.
  void openSearch({bool focus = true}) {
    if (_disposed || !selectedCapabilities.search) return;
    final current = _search.value;
    if (!current.isOpen) {
      _search.value = PanelSearchState(isOpen: true, wantsFocus: focus);
      _events.publish(const SearchOpened());
    } else if (focus && !current.wantsFocus) {
      _search.value = current.copyWith(wantsFocus: true);
    }
  }

  /// Closes search mode, forgetting the query and the focus intent, and
  /// publishes [SearchClosed]. Does nothing when search is closed.
  void closeSearch() {
    if (_disposed || !_search.value.isOpen) return;
    _search.value = PanelSearchState.closed;
    _searchBusy.value = false;
    _events.publish(const SearchClosed());
  }

  /// Invokes the action [actionId] that the selected page [pageId] declares,
  /// as a tap on its bottom-bar button does.
  ///
  /// The backspace action publishes [BackspaceRequested], the search action
  /// opens search, and any other publishes [ActionInvoked]. Ignored unless
  /// [pageId] is the selected page and declares [actionId]: only the selected
  /// page's actions are on screen.
  void invokeAction(String pageId, String actionId) {
    if (_disposed || pageId != _selected.value) return;
    final declared = selectedCapabilities.actions.any(
      (action) => action.id == actionId,
    );
    if (!declared) return;
    switch (actionId) {
      case PageAction.backspaceId:
        _events.publish(const BackspaceRequested());
      case PageAction.searchId:
        openSearch();
      default:
        _events.publish(ActionInvoked(pageId: pageId, actionId: actionId));
    }
  }

  /// Replaces the query while search is open. Ignored while it is closed:
  /// text has no place to go.
  void setQuery(String query) {
    if (_disposed) return;
    final current = _search.value;
    if (!current.isOpen || current.query == query) return;
    _search.value = current.copyWith(query: query);
  }

  /// Asks the search field to take focus. Does nothing unless search is open.
  void requestSearchFocus() {
    if (_disposed) return;
    final current = _search.value;
    if (!current.isOpen || current.wantsFocus) return;
    _search.value = current.copyWith(wantsFocus: true);
  }

  /// Withdraws the focus intent, as the field does when it loses focus (the
  /// soft keyboard was dismissed). Search stays open.
  void releaseSearchFocus() {
    if (_disposed) return;
    final current = _search.value;
    if (!current.wantsFocus) return;
    _search.value = current.copyWith(wantsFocus: false);
  }

  /// Steps back by one level of the shell's own state: closes search.
  ///
  /// Returns whether it consumed the press. When it did not, the shell has
  /// nothing left to dismiss and the caller (a presentation) closes the panel.
  bool handleBack() {
    if (_disposed || !_search.value.isOpen) return false;
    closeSearch();
    return true;
  }

  /// Reports how the presentation currently shows the panel.
  ///
  /// Called by the presentation controller that owns visibility, never by
  /// pages or widgets of the shell. Both observables change together in one
  /// call, each signalling only if its own value changed.
  void updatePresence({required bool visible, required bool opening}) {
    if (_disposed) return;
    _visible.value = visible;
    _opening.value = opening;
  }

  /// Reports that the panel is being opened afresh: every page is to come
  /// back as a new open shows it, which each page decides for itself (one
  /// goes back to its start, another keeps its place), and the bottom bar is
  /// shown.
  ///
  /// Called by the presentation controller that owns visibility when it
  /// opens a hidden panel under a presentation that opens afresh, before it
  /// reports the panel visible, so pages move while nothing of them is seen.
  /// Whether an open is fresh is the presentation's decision, never the
  /// shell's: a panel that keeps its place on every open never reports one.
  /// Changes no state of the shell; after [dispose] it is silent.
  void reportFreshOpen() {
    if (_disposed) return;
    _freshOpen.signal();
  }

  // --- Lifecycle ------------------------------------------------------------

  /// Drops every listener and, if the controller created it, disposes the
  /// page controller registry. Idempotent.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _selected.dispose();
    _search.dispose();
    _searchBusy.dispose();
    _visible.dispose();
    _opening.dispose();
    _freshOpen.dispose();
    _events.dispose();
    _scrollActivity.dispose();
    _searchResultCounts.dispose();
    _bottomExtent.dispose();
    _autoHideHolds.dispose();
    for (final guard in _deniedGuards.values) {
      guard.cancel();
    }
    _deniedGuards.clear();
    for (final listenable in _availabilityOf.values) {
      listenable.dispose();
    }
    _availability.dispose();
    _shown.dispose();
    for (final host in _hosts.values) {
      host.dispose();
    }
    _ownedControllers?.dispose();
  }

  // The selection change itself, shared by the user's selection and the
  // move off a page that stopped being available.
  void _moveTo(PanelPage page) {
    _selected.value = page.id;
    _bottomExtent.value = _bottomExtents[page.id] ?? 0;
    if (_search.value.isOpen && !_capabilitiesOf(page).search) closeSearch();
    _events.publish(PageChanged(page.id));
  }

  PageCapabilities _capabilitiesOf(PanelPage page) =>
      switch (_availability.value[page.id]!) {
        PageAvailability$Available() => page.capabilities,
        _ => PageCapabilities.none,
      };

  // A timer rather than a timestamp: it needs no clock, and a test's fake
  // time drives it.
  void _reportDenied(String pageId) {
    if (_deniedGuards.containsKey(pageId)) return;
    _deniedGuards[pageId] = Timer(
      deniedRepeatWindow,
      () => _deniedGuards.remove(pageId),
    );
    _events.publish(PageDenied(pageId));
  }

  // The first selectable page shown, in tab order.
  String? _fallback() {
    for (final page in _shown.value) {
      if (_availability.value[page.id]!.isSelectable) return page.id;
    }
    return null;
  }

  List<PanelPage> _shownOf(Map<String, PageAvailability> availability) {
    final shown = [
      for (final page in pages)
        if (availability[page.id]!.isShown) page,
    ];
    return List.unmodifiable(shown.isEmpty ? [pages.first] : shown);
  }

  static bool _sameIds(List<PanelPage> a, List<PanelPage> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id) return false;
    }
    return true;
  }

  Future<void> _persist(String pageId) async {
    try {
      await _preferences.setSelectedPageId(pageId);
    } on Object catch (error, stackTrace) {
      Zone.current.handleUncaughtError(error, stackTrace);
    }
  }
}

final class _PageHost with ChangeNotifier implements PanelPageHost {
  _PageHost(this._shell, PanelPage page)
    : pageId = page.id,
      isActive = _SelectedIs(_shell._selected, page.id);

  final PanelShellController _shell;
  @override
  final String pageId;

  @override
  final _SelectedIs isActive;

  @override
  ValueListenable<PanelSearchState> get search => _shell._search;

  @override
  Listenable get reselected => this;

  @override
  PageControllerRegistry get controllers => _shell.controllers;

  bool get _speaksForSelected =>
      !_shell._disposed && _shell._selected.value == pageId;

  @override
  void pick(
    ContentKey key, {
    required SemanticKind kind,
    SemanticKind? recentsKind,
    PickSource source = PickSource.collection,
  }) {
    if (_shell._disposed) return;
    _shell._events.publish(
      ContentPicked(
        key: key,
        kind: kind,
        recentsKind: recentsKind,
        source: source,
      ),
    );
  }

  @override
  void requestClearRecents(SemanticKind kind) {
    if (_shell._disposed) return;
    _shell._events.publish(ClearRecentsRequested(kind: kind));
  }

  @override
  void requestCopy(ContentKey key, {required SemanticKind kind}) {
    if (_shell._disposed) return;
    _shell._events.publish(ContentCopyRequested(key: key, kind: kind));
  }

  @override
  void requestRemoveRecent(ContentKey key, {required SemanticKind kind}) {
    if (_shell._disposed) return;
    _shell._events.publish(RecentRemoveRequested(key: key, kind: kind));
  }

  @override
  void requestLibraryEdit(LibraryEdit edit) {
    if (_shell._disposed) return;
    _shell._events.publish(LibraryEditRequested(edit));
  }

  @override
  void requestPack(PackId id) {
    if (_shell._disposed) return;
    _shell._events.publish(PackRequested(id));
  }

  @override
  PanelPageHold holdAutoHide() {
    final hold = _Hold(_shell);
    if (!_shell._disposed) _shell._autoHideHolds.value++;
    return hold;
  }

  @override
  ValueListenable<bool> get panelVisible => _shell._visible;

  @override
  ValueListenable<bool> get panelOpening => _shell._opening;

  @override
  Listenable get freshOpen => _shell._freshOpen;

  @override
  void releaseSearchFocus() {
    if (_speaksForSelected) _shell.releaseSearchFocus();
  }

  @override
  void reportScrollActivity(PageScrollActivity activity) {
    if (_speaksForSelected) _shell._scrollActivity.publish(activity);
  }

  @override
  void reportSearchProgress({required bool busy}) {
    if (_speaksForSelected) _shell._searchBusy.value = busy;
  }

  @override
  void reportSearchResultCount(int count) {
    if (_speaksForSelected) _shell._searchResultCounts.publish(count);
  }

  // Kept per page, unlike the other reports: the strip of a page that is not
  // selected is still there when the page comes back, and the page does not
  // report again for a layout that did not change.
  @override
  void reportBottomExtent(double extent) {
    if (_shell._disposed) return;
    _shell._bottomExtents[pageId] = extent;
    if (_speaksForSelected) _shell._bottomExtent.value = extent;
  }

  void _reselect() => notifyListeners();

  // The shell disposes a host once, with itself.
  @override
  void dispose() {
    isActive.dispose();
    super.dispose();
  }
}

final class _Hold implements PanelPageHold {
  _Hold(this._shell) : _counted = !_shell._disposed;

  final PanelShellController _shell;

  // A hold taken after dispose never counted, and releasing it must not count
  // down.
  final bool _counted;
  var _released = false;

  @override
  void release() {
    if (_released) return;
    _released = true;
    if (_counted && !_shell._disposed) _shell._autoHideHolds.value--;
  }
}

/// A signal without a value: `notifyListeners` is protected, so the controller
/// reaches it through this subclass.
final class _Signal with ChangeNotifier {
  void signal() => notifyListeners();
}

/// The availability of one page out of the map of all, signalling only when
/// that page's changes.
final class _AvailabilityOf
    with ChangeNotifier
    implements ValueListenable<PageAvailability> {
  _AvailabilityOf(this._source, this._id) : _value = _source.value[_id]! {
    _source.addListener(_onSource);
  }

  final ValueNotifier<Map<String, PageAvailability>> _source;
  final String _id;
  PageAvailability _value;

  void _onSource() {
    final next = _source.value[_id]!;
    if (next == _value) return;
    _value = next;
    notifyListeners();
  }

  @override
  PageAvailability get value => _value;

  @override
  void dispose() {
    _source.removeListener(_onSource);
    super.dispose();
  }
}

/// Whether the observed page id equals [id]; signals only when that answer
/// changes, so a page's `isActive` listeners do not wake for other pages.
final class _SelectedIs with ChangeNotifier implements ValueListenable<bool> {
  _SelectedIs(this._source, this._id) : _answer = _source.value == _id {
    _source.addListener(_onSource);
  }

  final ValueNotifier<String> _source;
  final String _id;
  bool _answer;

  void _onSource() {
    final next = _source.value == _id;
    if (next == _answer) return;
    _answer = next;
    notifyListeners();
  }

  @override
  bool get value => _answer;

  @override
  void dispose() {
    _source.removeListener(_onSource);
    super.dispose();
  }
}
