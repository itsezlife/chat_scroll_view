import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view_example/src/features/chat/controller/chat_search_state.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/chat_message_search.dart';
import 'package:control/control.dart';

/// Global in-chat search over the full known message range.
///
/// Concurrent by default; a generation token supersedes in-flight scans when
/// the user submits a newer query (latest-wins without a controller-wide
/// droppable policy).
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

  /// Older hit (Telegram search-up).
  void goOlder() {
    state.maybeMap(
      populated: (s) {
        if (s.index <= 0) return;
        setState(s.copyWith(index: s.index - 1));
      },
      orElse: () {},
    );
  }

  /// Newer hit (Telegram search-down).
  void goNewer() {
    state.maybeMap(
      populated: (s) {
        if (s.index >= s.hits.length - 1) return;
        setState(s.copyWith(index: s.index + 1));
      },
      orElse: () {},
    );
  }

  /// Active hit message id, if any.
  int? get activeHitId =>
      state.maybeMap(populated: (s) => s.hits[s.index], orElse: () => null);
}
