import 'package:content_model/content_model.dart';
import 'package:panel_shell/panel_shell.dart';
import 'package:panel_shell/testing.dart';

/// A [PanelPageHost] for tests of a page: the observables are settable and
/// every report the page makes is recorded.
///
/// Unlike the shell's real host, it drops nothing: reports of a page that is
/// not active are kept too, so a test sees what the page said and decides
/// whether the shell would have listened.
final class FakePanelPageHost implements PanelPageHost {
  /// A host for the page [pageId].
  FakePanelPageHost({this.pageId = 'page'});

  @override
  final String pageId;

  final _search = ObservableValue<PanelSearchState>(PanelSearchState.closed);
  final _isActive = ObservableValue<bool>(true);
  final _reselected = ObservableNotifier();

  @override
  final FakePageControllerRegistry controllers = FakePageControllerRegistry();

  /// Every pick the page reported, in order.
  final List<({ContentKey key, SemanticKind kind, PickSource source})> picks =
      [];

  /// Every clear-recents request, in order.
  final List<SemanticKind> clearRecentsRequests = [];

  /// Every scroll activity the page reported, in order.
  final List<PageScrollActivity> scrollActivity = [];

  /// Every search-progress report, in order.
  final List<bool> searchProgress = [];

  /// Every search result count the page reported, in order.
  final List<int> searchResultCounts = [];

  @override
  ValueObservable<PanelSearchState> get search => _search;

  @override
  ValueObservable<bool> get isActive => _isActive;

  @override
  Observable get reselected => _reselected;

  /// Sets the search state the page follows.
  set searchState(PanelSearchState state) => _search.value = state;

  /// Sets whether the page is the selected one.
  set active(bool value) => _isActive.value = value;

  /// Signals that the user selected the tab of this page again.
  void reselect() => _reselected.notify();

  @override
  void pick(
    ContentKey key, {
    required SemanticKind kind,
    PickSource source = PickSource.collection,
  }) => picks.add((key: key, kind: kind, source: source));

  @override
  void requestClearRecents(SemanticKind kind) => clearRecentsRequests.add(kind);

  @override
  void reportScrollActivity(PageScrollActivity activity) =>
      scrollActivity.add(activity);

  @override
  void reportSearchProgress({required bool busy}) => searchProgress.add(busy);

  @override
  void reportSearchResultCount(int count) => searchResultCounts.add(count);

  /// Releases the observables.
  void dispose() {
    _search.dispose();
    _isActive.dispose();
    _reselected.dispose();
  }
}
