import 'package:chat_scroll_view_example/src/features/chat/data/bundled_packs.dart';
import 'package:content_model/content_model.dart';
import 'package:listen/listen.dart' as listen;

/// The recent stickers, or the recent GIFs, as the one collection a page lists
/// ahead of its packs: `CollectionId.recent`, loaded from the start.
///
/// The list is the [recents] store's for [kind], best first; what is on it is
/// described by `describe` (the bundled packs unless the host passes its own,
/// which also knows content from elsewhere). A key nothing describes (a pack
/// the host no longer ships, a feed's clip this session never listed) is left
/// out rather than listed as a cell nothing can draw.
///
/// The collection is published again whenever [recents] changes. A host that
/// does not want the page to reorder under the finger that is picking from it
/// passes the deferred view of its store (`DeferredRecentsStore`), which
/// publishes when the host commits.
///
/// It owns nothing: [dispose] only stops listening.
final class RecentContentSource implements CollectionSource {
  /// Lists the [kind] list of [recents].
  RecentContentSource({
    required RecentsStore recents,
    required this.kind,
    DescribeContent describe = BundledPacks.describe,
  }) : _recents = recents,
       _describe = describe {
    _collections = listen.ValueNotifier(_collect());
    recents.changes.addListener(_republish);
  }

  /// Which list of the store this is: stickers or GIFs.
  final SemanticKind kind;

  final RecentsStore _recents;
  final DescribeContent _describe;
  late final listen.ValueNotifier<List<Collection>> _collections;
  var _disposed = false;

  @override
  listen.ValueListenable<List<Collection>> get collections => _collections;

  // Everything is in memory: there is nothing to load, and no page after the
  // first.
  @override
  Future<void> load(CollectionId id) async {}

  @override
  Future<void> loadMore(CollectionId id) async {}

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _recents.changes.removeListener(_republish);
    _collections.dispose();
  }

  void _republish() {
    if (_disposed) return;
    _collections.value = _collect();
  }

  List<Collection> _collect() => [
    Collection(
      id: CollectionId.recent,
      metadata: const CollectionMetadata(flags: CollectionFlags.installed),
      contents: CollectionContents.loaded([
        for (final key in _recents.recents(kind))
          if (_describe(key) case final descriptor?)
            CollectionItem.described(descriptor),
      ]),
    ),
  ];
}
