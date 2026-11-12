import 'package:content_model/content_model.dart';
import 'package:listen/listen.dart' as listen;

/// One item of a bundled pack: what the host tells its asset pipeline, and
/// where the app bundle holds the file. [BundledPacks] finds items by [key]
/// for both the fetcher and the resolver.
///
/// [BundledPacks]: bundled_packs.dart
abstract interface class BundledItem {
  /// The item's content identity.
  ContentKey get key;

  /// What the pipeline needs to make it.
  ContentDescriptor get descriptor;

  /// Where the bundle holds the file.
  String get assetPath;
}

/// A source that lists one bundled pack as an installed collection, loaded
/// from the start: everything it holds is in the bundle, so there is nothing
/// to wait for and no page after the first.
final class BundledPackSource implements CollectionSource {
  /// Creates a source of the collection [id], titled [title], of [items].
  BundledPackSource({
    required CollectionId id,
    required String title,
    required Iterable<BundledItem> items,
  }) : _collections = listen.ValueNotifier(
         List.unmodifiable([
           Collection(
             id: id,
             metadata: CollectionMetadata(
               title: title,
               flags: CollectionFlags.installed,
             ),
             contents: CollectionContents.loaded([
               for (final item in items)
                 CollectionItem.described(item.descriptor),
             ]),
           ),
         ]),
       );

  final listen.ValueNotifier<List<Collection>> _collections;

  @override
  listen.ValueListenable<List<Collection>> get collections => _collections;

  @override
  Future<void> load(CollectionId id) async {}

  @override
  Future<void> loadMore(CollectionId id) async {}

  @override
  void dispose() => _collections.dispose();
}
