import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view_example/src/features/chat/controller/chat_search_state.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/chat_message_search.dart';
import 'package:control/control.dart';

/// One step candidate from [ChatSearchController.peekOlder] /
/// [ChatSearchController.peekNewer].
typedef ChatSearchStep = ({int index, int id});

/// Global in-chat search over the full known message range.
///
/// Concurrent by default; a generation token supersedes in-flight scans when
/// the user submits a newer query (latest-wins without a controller-wide
/// droppable policy).
///
/// Hit [ChatSearchState.populated.index] is the **committed** selection —
/// the last target the host successfully handed to the viewport. Step taps
/// must [peekOlder]/[peekNewer], call [ChatScrollController.animateTo], and
/// only [selectIndex] when disposition is not [AnimateToDisposition.ignored].
/// Advancing the index before [animateTo] under [AnimateToBusyPolicy.ignore]
/// races selection ahead of the viewport and disables bound-gated chrome.
final class ChatSearchController extends StateController<ChatSearchState> {
  /// Creates a search controller bound to [dataSource].
  ChatSearchController({
    required ChatDataSource dataSource,
    ChatSearchState? initialState,
  }) : _dataSource = dataSource,
       super(initialState: initialState ?? const ChatSearchState.closed());

  final ChatDataSource _dataSource;

  /// Monotonic id of the latest [submit] — stale scans bail before [setState].
  var _searchGeneration = 0;

  /// Opens the search chrome with an idle (empty) query.
  void open() {
    state.maybeMap(
      closed: (_) => setState(const ChatSearchState.idle()),
      orElse: () {},
    );
  }

  /// Hides the search chrome and clears results.
  void close() {
    _searchGeneration++;
    setState(const ChatSearchState.closed());
  }

  /// Scans all messages for [rawQuery] and lands on the newest hit.
  void submit(String rawQuery) {
    final query = rawQuery.trim();
    if (query.isEmpty) {
      state.maybeMap(
        closed: (_) {},
        orElse: () => setState(const ChatSearchState.idle()),
      );
      return;
    }

    final generation = ++_searchGeneration;
    handle(
      () => _runSearch(query, generation),
      error: (error, _) async {
        if (generation != _searchGeneration) return;
        setState(ChatSearchState.failure(query: query, error: error));
      },
      name: 'search',
      meta: {'query': query, 'generation': generation},
    );
  }

  Future<void> _runSearch(String query, int generation) async {
    setState(ChatSearchState.searching(query: query));
    final hits = await searchAllMessageIds(
      _dataSource,
      query,
      isCancelled: () => generation != _searchGeneration,
    );
    if (generation != _searchGeneration) return;

    if (hits.isEmpty) {
      setState(ChatSearchState.empty(query: query));
      return;
    }
    setState(
      ChatSearchState.populated(
        query: query,
        hits: List<int>.unmodifiable(hits),
        index: hits.length - 1,
      ),
    );
  }

  /// Next older hit without mutating state, or `null` at the bound.
  ChatSearchStep? peekOlder() => state.maybeMap(
    populated: (s) {
      if (s.index <= 0) return null;
      final index = s.index - 1;
      return (index: index, id: s.hits[index]);
    },
    orElse: () => null,
  );

  /// Next newer hit without mutating state, or `null` at the bound.
  ChatSearchStep? peekNewer() => state.maybeMap(
    populated: (s) {
      if (s.index >= s.hits.length - 1) return null;
      final index = s.index + 1;
      return (index: index, id: s.hits[index]);
    },
    orElse: () => null,
  );

  /// Commits [index] as the active hit (after viewport navigation accepted).
  void selectIndex(int index) {
    state.maybeMap(
      populated: (s) {
        if (index < 0 || index >= s.hits.length) return;
        if (index == s.index) return;
        setState(s.copyWith(index: index));
      },
      orElse: () {},
    );
  }

  /// Older hit (Telegram search-up). Prefer [peekOlder] + [selectIndex] when
  /// pairing with [AnimateToBusyPolicy.ignore].
  void goOlder() {
    final step = peekOlder();
    if (step == null) return;
    selectIndex(step.index);
  }

  /// Newer hit (Telegram search-down). Prefer [peekNewer] + [selectIndex] when
  /// pairing with [AnimateToBusyPolicy.ignore].
  void goNewer() {
    final step = peekNewer();
    if (step == null) return;
    selectIndex(step.index);
  }

  /// Active hit message id, if any.
  int? get activeHitId =>
      state.maybeMap(populated: (s) => s.hits[s.index], orElse: () => null);

  /// Whether search chrome is visible (any state except [ChatSearchState.closed]).
  bool get isOpen =>
      state.maybeMap(closed: (_) => false, orElse: () => true);
}
