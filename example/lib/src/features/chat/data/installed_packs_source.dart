import 'package:content_model/content_model.dart';
import 'package:listen/listen.dart' as listen;

/// The packs of one [PackKind] the user installed, in the content library's
/// order, as the collections a panel page lists: the stickers page's packs,
/// the emoji page's packs of custom emoji.
///
/// The library says which packs and in what order
/// (`ContentLibrary.installedPacks`); the [PackSource] says what each holds.
/// A pack still being looked up is listed loading (the page shows its
/// skeleton), a pack the source cannot find is left out, and a pack added
/// or removed in a pack sheet comes and goes at once: a page lists what
/// the user has, not every pack the host knows.
///
/// It owns nothing: [dispose] only stops listening.
final class InstalledPacksSource implements CollectionSource {
  /// The installed packs of [kind] in [library], resolved through [packs].
  InstalledPacksSource({
    required this.kind,
    required ContentLibrary library,
    required PackSource packs,
  }) : _installed = library.installedPacks(kind),
       _packs = packs {
    _collections = listen.ValueNotifier(_collect());
    _installed.addListener(_republish);
    _packs.changes.addListener(_republish);
    _lookUpNew();
  }

  /// The kind of packs listed.
  final PackKind kind;

  final listen.ValueListenable<List<PackId>> _installed;
  final PackSource _packs;
  late final listen.ValueNotifier<List<Collection>> _collections;
  var _disposed = false;

  @override
  listen.ValueListenable<List<Collection>> get collections => _collections;

  // The page asks as a pack comes near; a pack is looked up once listed
  // anyway, so this only retries one that failed.
  @override
  Future<void> load(CollectionId id) async {
    if (id case CollectionId$Set(:final id)) {
      await _packs.lookup(PackId(id));
    }
  }

  // A pack is one page.
  @override
  Future<void> loadMore(CollectionId id) async {}

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _installed.removeListener(_republish);
    _packs.changes.removeListener(_republish);
    _collections.dispose();
  }

  void _republish() {
    if (_disposed) return;
    _collections.value = _collect();
    _lookUpNew();
  }

  // Each listed pack nobody asked for yet; the answer arrives through the
  // source's changes, which publish again.
  void _lookUpNew() {
    for (final id in _installed.value) {
      if (_packs.peek(id) case PackLookup$Idle()) _packs.lookup(id).ignore();
    }
  }

  List<Collection> _collect() => List.unmodifiable(
    [
      for (final id in _installed.value)
        switch (_packs.peek(id)) {
          PackLookup$Found(:final pack) => _installedCollection(pack),
          PackLookup$Idle() || PackLookup$Loading() => _loading(id),
          PackLookup$NotFound() || PackLookup$Failed() => null,
        },
    ].nonNulls,
  );

  static Collection _loading(PackId id) => Collection(
    id: CollectionId.set(id.value),
    metadata: const CollectionMetadata(flags: CollectionFlags.installed),
    contents: CollectionContents.loading,
  );

  static Collection _installedCollection(Pack pack) {
    final collection = pack.collection;
    return Collection(
      id: collection.id,
      metadata: CollectionMetadata(
        title: pack.title,
        cover: pack.cover,
        flags: pack.official
            ? CollectionFlags.installed | CollectionFlags.official
            : CollectionFlags.installed,
      ),
      contents: collection.contents,
    );
  }
}
