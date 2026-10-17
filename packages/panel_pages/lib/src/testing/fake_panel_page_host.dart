import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter/widgets.dart'
    show BuildContext, State, StatefulWidget, Widget;
import 'package:listen/listen.dart';
import 'package:panel_shell/panel_shell.dart';
import 'package:panel_shell/testing.dart';

final class _FakeHold implements PanelPageHold {
  _FakeHold(this._onRelease);

  final void Function() _onRelease;
  var _released = false;

  @override
  void release() {
    if (_released) return;
    _released = true;
    _onRelease();
  }
}

/// A [PanelPageHost] for tests of a page: the listenables are settable and
/// every report the page makes is recorded.
///
/// Unlike the shell's real host, it drops nothing: reports of a page that is
/// not active are kept too, so a test sees what the page said and decides
/// whether the shell would have listened.
final class FakePanelPageHost with ChangeNotifier implements PanelPageHost {
  /// A host for the page [pageId].
  FakePanelPageHost({this.pageId = 'page'});

  @override
  final String pageId;

  final _search = ValueNotifier<PanelSearchState>(PanelSearchState.closed);
  final _isActive = ValueNotifier<bool>(true);
  var _disposed = false;
  final _panelVisible = ValueNotifier<bool>(true);
  final _panelOpening = ValueNotifier<bool>(false);

  @override
  final FakePageControllerRegistry controllers = FakePageControllerRegistry();

  /// Every pick the page reported, in order.
  final List<
    ({
      ContentKey key,
      SemanticKind kind,
      SemanticKind recentsKind,
      PickSource source,
    })
  >
  picks = [];

  /// Every clear-recents request, in order.
  final List<SemanticKind> clearRecentsRequests = [];

  /// Every copy request, in order.
  final List<({ContentKey key, SemanticKind kind})> copyRequests = [];

  /// Every remove-from-recent request, in order.
  final List<({ContentKey key, SemanticKind kind})> removeRecentRequests = [];

  /// How many holds on auto-hide the page took in all.
  int holdsTaken = 0;

  /// How many holds the page keeps now: taken and not yet released.
  int get activeHolds => _activeHolds;
  int _activeHolds = 0;

  /// Every scroll activity the page reported, in order.
  final List<PageScrollActivity> scrollActivity = [];

  /// How many times the page released the search focus.
  int searchFocusReleases = 0;

  /// Every search-progress report, in order.
  final List<bool> searchProgress = [];

  /// Every search result count the page reported, in order.
  final List<int> searchResultCounts = [];

  /// Every bottom extent the page reported, in order.
  final List<double> bottomExtents = [];

  @override
  ValueListenable<PanelSearchState> get search => _search;

  @override
  ValueListenable<bool> get isActive => _isActive;

  @override
  Listenable get reselected => this;

  /// Whether the panel is shown; true unless a test hides it.
  @override
  ValueListenable<bool> get panelVisible => _panelVisible;

  /// Whether the panel is moving; false unless a test moves it.
  @override
  ValueListenable<bool> get panelOpening => _panelOpening;

  /// Sets whether the panel is on screen.
  set visible(bool value) => _panelVisible.value = value;

  /// Sets whether the panel is moving.
  set opening(bool value) => _panelOpening.value = value;

  /// Sets the search state the page follows.
  set searchState(PanelSearchState state) => _search.value = state;

  /// Sets whether the page is the selected one.
  set active(bool value) => _isActive.value = value;

  /// Signals that the user selected the tab of this page again.
  void reselect() => notifyListeners();

  @override
  void pick(
    ContentKey key, {
    required SemanticKind kind,
    SemanticKind? recentsKind,
    PickSource source = PickSource.collection,
  }) => picks.add((
    key: key,
    kind: kind,
    recentsKind: recentsKind ?? kind,
    source: source,
  ));

  @override
  void requestClearRecents(SemanticKind kind) => clearRecentsRequests.add(kind);

  @override
  void requestCopy(ContentKey key, {required SemanticKind kind}) =>
      copyRequests.add((key: key, kind: kind));

  @override
  void requestRemoveRecent(ContentKey key, {required SemanticKind kind}) =>
      removeRecentRequests.add((key: key, kind: kind));

  @override
  PanelPageHold holdAutoHide() {
    holdsTaken++;
    _activeHolds++;
    return _FakeHold(() => _activeHolds--);
  }

  @override
  void releaseSearchFocus() => searchFocusReleases++;

  @override
  void reportScrollActivity(PageScrollActivity activity) =>
      scrollActivity.add(activity);

  @override
  void reportSearchProgress({required bool busy}) => searchProgress.add(busy);

  @override
  void reportSearchResultCount(int count) => searchResultCounts.add(count);

  @override
  void reportBottomExtent(double extent) => bottomExtents.add(extent);

  /// Releases the listenables. Idempotent.
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _search.dispose();
    _isActive.dispose();
    _panelVisible.dispose();
    _panelOpening.dispose();
    super.dispose();
  }
}

/// What a page that places the shell's search field inline needs above it when
/// a test mounts the page without a shell: a `PanelSearchFieldScope` over a
/// controller of its own.
///
/// The field projects that controller, not the [FakePanelPageHost] the page was
/// built with, so a test that drives the field drives the controller, and one
/// that drives the page sets the host's search state.
class FakeSearchFieldScope extends StatefulWidget {
  /// Provides a search field scope to [child].
  const FakeSearchFieldScope({required this.child, super.key});

  /// The subtree that contains the page.
  final Widget child;

  @override
  State<FakeSearchFieldScope> createState() => _FakeSearchFieldScopeState();
}

class _FakeSearchFieldScopeState extends State<FakeSearchFieldScope> {
  late final FakePreferenceStore _preferences = FakePreferenceStore();
  late final PanelShellController _controller = PanelShellController(
    pages: [FakePanelPage('fake', search: true).page],
    preferences: _preferences,
  );

  @override
  void dispose() {
    _controller.dispose();
    _preferences.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PanelSearchFieldScope(
    controller: _controller,
    contextMenuBuilder: null,
    child: widget.child,
  );
}
