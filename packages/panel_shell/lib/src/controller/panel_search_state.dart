import 'package:meta/meta.dart';

/// The search state of the panel: one snapshot of whether search mode is
/// open, what the query is and whether the field should hold focus.
///
/// The three fields live in one value so a consumer never sees a half-applied
/// change, such as an open search with the previous session's query.
@immutable
final class PanelSearchState {
  /// A search state with the given parts.
  const PanelSearchState({
    this.isOpen = false,
    this.query = '',
    this.wantsFocus = false,
  });

  /// Search mode off: no query, no focus intent.
  static const PanelSearchState closed = PanelSearchState();

  /// Whether search mode is open.
  final bool isOpen;

  /// The text of the search field, as typed. Empty when closed.
  final String query;

  /// The **focus intent**: whether the search field should hold focus. The
  /// field widget realises it; losing focus (the soft keyboard was dismissed)
  /// withdraws it without closing search.
  final bool wantsFocus;

  /// A copy with the named parts replaced.
  PanelSearchState copyWith({bool? isOpen, String? query, bool? wantsFocus}) =>
      PanelSearchState(
        isOpen: isOpen ?? this.isOpen,
        query: query ?? this.query,
        wantsFocus: wantsFocus ?? this.wantsFocus,
      );

  @override
  bool operator ==(Object other) =>
      other is PanelSearchState &&
      other.isOpen == isOpen &&
      other.query == query &&
      other.wantsFocus == wantsFocus;

  @override
  int get hashCode => Object.hash(isOpen, query, wantsFocus);

  @override
  String toString() =>
      'PanelSearchState(isOpen: $isOpen, query: "$query", '
      'wantsFocus: $wantsFocus)';
}
