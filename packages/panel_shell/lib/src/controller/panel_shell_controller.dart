import 'dart:async';

import 'package:content_model/content_model.dart';
import 'package:listen/listen.dart';
import 'package:panel_shell/src/controller/event_publisher.dart';
import 'package:panel_shell/src/controller/panel_search_state.dart';
import 'package:panel_shell/src/event/panel_event.dart';
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
/// [PanelEvent]s, and the **presence** (visible, opening) a presentation
/// reports so a host can wire the pause signals of work that must not run
/// while the panel is hidden or moving.
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
/// falls back to the first page. A failure to persist is reported to the zone
/// and leaves the in-memory selection as it is.
final class PanelShellController {
  /// Creates a controller over [pages], in tab order.
  ///
  /// [preferences] is already loaded, so the remembered page is known
  /// synchronously. [controllers] lets a test or host supply the registry;
  /// when omitted the controller creates one and disposes it. A supplied
  /// registry is left to its owner.
  ///
  /// Throws an [ArgumentError] for an empty [pages] or a repeated page id.
  factory PanelShellController({
    required List<PanelPage> pages,
    required PreferenceStore preferences,
    PageControllerRegistry? controllers,
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
    );
  }

  PanelShellController._(
    List<PanelPage> pages,
    PreferenceStore preferences,
    this.controllers,
    this._ownedControllers,
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
    final remembered = preferences.selectedPageId;
    _selected = ValueNotifier<String>(
      remembered != null && _byId.containsKey(remembered)
          ? remembered
          : pages.first.id,
    );
  }

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
  final _events = EventPublisher<PanelEvent>();
  final _scrollActivity = EventPublisher<PageScrollActivity>();
  final _searchResultCounts = EventPublisher<int>();
  final _hosts = <String, _PageHost>{};
  var _disposed = false;

  /// The id of the selected page.
  ValueListenable<String> get selectedPageId => _selected;

  /// The selected page.
  PanelPage get selectedPage => _byId[_selected.value]!;

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

  /// **Panel visible**: whether a presentation shows the panel on screen,
  /// including while it slides in or out. The pause signal of work that is
  /// pointless when nothing is seen.
  ValueListenable<bool> get visible => _visible;

  /// **Panel opening**: whether the panel is moving in or out. The pause
  /// signal of work that would drop frames during the motion.
  ValueListenable<bool> get opening => _opening;

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

  // --- Intents --------------------------------------------------------------

  /// Selects the page [pageId].
  ///
  /// Persists the id, closes search if the new page declares none, and
  /// publishes [PageChanged]. Selecting the page that is already selected
  /// changes nothing but signals that page's `reselected`. An id that is not
  /// registered is ignored.
  void selectPage(String pageId) {
    if (_disposed) return;
    final page = _byId[pageId];
    if (page == null) return;
    if (pageId == _selected.value) {
      _hosts[pageId]?._reselect();
      return;
    }
    _selected.value = pageId;
    if (_search.value.isOpen && !page.capabilities.search) closeSearch();
    unawaited(_persist(pageId));
    _events.publish(PageChanged(pageId));
  }

  /// Opens search mode above the selected page.
  ///
  /// Does nothing when the selected page does not declare search. With
  /// [focus] the field is asked to take focus; calling again on an open
  /// search with [focus] only adds the focus intent. Publishes [SearchOpened]
  /// when it opened.
  void openSearch({bool focus = true}) {
    if (_disposed || !selectedPage.capabilities.search) return;
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
    final declared = selectedPage.capabilities.actions.any(
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
    _events.dispose();
    _scrollActivity.dispose();
    _searchResultCounts.dispose();
    for (final host in _hosts.values) {
      host.dispose();
    }
    _ownedControllers?.dispose();
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
    PickSource source = PickSource.collection,
  }) {
    if (_shell._disposed) return;
    _shell._events.publish(ContentPicked(key: key, kind: kind, source: source));
  }

  @override
  void requestClearRecents(SemanticKind kind) {
    if (_shell._disposed) return;
    _shell._events.publish(ClearRecentsRequested(kind: kind));
  }

  @override
  ValueListenable<bool> get panelVisible => _shell._visible;

  @override
  ValueListenable<bool> get panelOpening => _shell._opening;

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

  void _reselect() => notifyListeners();

  // The shell disposes a host once, with itself.
  @override
  void dispose() {
    isActive.dispose();
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
