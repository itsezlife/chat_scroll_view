import 'package:freezed_annotation/freezed_annotation.dart';

part 'chat_search_state.freezed.dart';

/// UI + result modes for in-chat global message search.
@freezed
abstract class ChatSearchState with _$ChatSearchState {
  /// Search chrome is hidden.
  const factory ChatSearchState.closed() = _ChatSearchClosed;

  /// Search chrome is open; no query submitted yet.
  const factory ChatSearchState.idle() = _ChatSearchIdle;

  /// Scanning the full message range for [query].
  const factory ChatSearchState.searching({required String query}) =
      _ChatSearchSearching;

  /// Non-empty hit list for [query]; [index] is the active hit.
  const factory ChatSearchState.populated({
    required String query,
    required List<int> hits,
    required int index,
  }) = _ChatSearchPopulated;

  /// Scan finished with zero matches for [query].
  const factory ChatSearchState.empty({required String query}) =
      _ChatSearchEmpty;

  /// Scan failed for [query].
  const factory ChatSearchState.failure({
    required String query,
    required Object error,
  }) = _ChatSearchFailure;
}
