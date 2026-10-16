import 'package:content_model/content_model.dart';

/// The pages a fake source serves for one collection or query: the first page
/// on load, then one more per `loadMore`, each named by a [PageToken].
final class FakePages {
  /// Creates pages from [pages], in the order they are served.
  const FakePages(this.pages);

  /// No items at all: a loaded, empty first page with no next one.
  static const FakePages none = FakePages([]);

  /// The items of each page.
  final List<List<CollectionItem>> pages;

  /// The first page as loaded contents.
  CollectionContents$Loaded first() => CollectionContents$Loaded(
    pages.isEmpty ? const [] : pages.first,
    nextPageToken: _tokenFor(1),
  );

  /// [current] with the page its token names appended, or null when it has no
  /// token or the token names no page.
  CollectionContents$Loaded? more(CollectionContents$Loaded current) {
    final token = current.nextPageToken;
    final index = token == null ? null : int.tryParse(token.value);
    if (index == null || index < 1 || index >= pages.length) return null;
    return CollectionContents$Loaded([
      ...current.items,
      ...pages[index],
    ], nextPageToken: _tokenFor(index + 1));
  }

  PageToken? _tokenFor(int index) =>
      index < pages.length ? PageToken('$index') : null;
}
