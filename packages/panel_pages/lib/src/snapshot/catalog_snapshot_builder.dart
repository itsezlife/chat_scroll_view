import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/content_model.dart';
import 'package:panel_catalog/panel_catalog.dart';
import 'package:panel_pages/src/policy/catalog_page_policy.dart';

/// Builds the viewport's [CatalogSnapshot] from the collections a page shows.
///
/// One collection is one section, and the section mirrors the collection's
/// state with no error UI of its own:
///
/// | Collection contents | Section |
/// | --- | --- |
/// | idle, loading | `loading`: skeleton cells, no leaves |
/// | failed (first load) | `failed`: the same skeletons; a retry is the page's |
/// | loaded, with items | `loaded`: one leaf per item, in order |
/// | loaded, empty | `loaded`: the policy's empty message, or the header alone |
///
/// Everything that depends on the kind of content (ids, titles, geometry, leaf
/// facts, the empty message, the header action) is the [CatalogPagePolicy]'s.
/// The builder holds no layout maths: sizes and offsets are the viewport's.
///
/// It remembers the collection behind each section of its last build, which is
/// how an interaction addressed by section id finds the collection again.
final class CatalogSnapshotBuilder {
  /// A builder that asks [policy] for everything content-specific.
  CatalogSnapshotBuilder({required this.policy});

  /// The policy this builder asks; replaceable while the page lives.
  CatalogPagePolicy policy;

  var _collections = const <String, Collection>{};

  /// The snapshot of [collections], in order, in the language of [strings].
  CatalogSnapshot build(
    List<Collection> collections, {
    required PanelStrings strings,
  }) {
    final byId = <String, Collection>{};
    final sections = <CatalogSection>[];
    for (final collection in collections) {
      final id = policy.sectionIdOf(collection);
      byId[id] = collection;
      sections.add(_sectionOf(id, collection, strings));
    }
    _collections = byId;
    return CatalogSnapshot(sections);
  }

  /// The collection behind section [sectionId] in the last build, or null.
  Collection? collectionOf(String sectionId) => _collections[sectionId];

  CatalogSection _sectionOf(
    String id,
    Collection collection,
    PanelStrings strings,
  ) {
    final contents = collection.contents;
    final loaded = switch (contents) {
      CollectionContents$Loaded() => true,
      _ => false,
    };
    return CatalogSection(
      id: id,
      title: policy.titleOf(collection, strings),
      leaves: switch (contents) {
        CollectionContents$Loaded(:final items) => [
          for (final item in items) policy.leafOf(item, collection),
        ],
        _ => const [],
      },
      layout: policy.layoutOf(collection),
      contentBox: policy.contentBoxOf(collection),
      placeholderStyle: policy.placeholderStyleOf(collection),
      state: switch (contents) {
        CollectionContents$Failed() => CatalogSectionState.failed,
        CollectionContents$Loaded() => CatalogSectionState.loaded,
        _ => CatalogSectionState.loading,
      },
      skeletonCount: loaded ? null : policy.skeletonCountOf(collection),
      emptyMessage: loaded ? policy.emptyMessageOf(collection, strings) : null,
      action: policy.actionOf(collection, strings),
    );
  }
}
