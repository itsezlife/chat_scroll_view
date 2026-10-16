import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:chrome_foundation/testing.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_catalog/panel_catalog.dart';
import 'package:panel_pages/panel_pages.dart';
import 'package:panel_shell/panel_shell.dart';

final _strings = ChromeStringsPresets.english.panel;

const _smile = ContentKey.unicode('😀');
const _sticker = ContentKey.document('7');

Collection _collection(
  CollectionId id, {
  CollectionContents contents = CollectionContents.idle,
  String? title,
}) => Collection(
  id: id,
  metadata: CollectionMetadata(title: title),
  contents: contents,
);

CollectionContents _loaded(List<CollectionItem> items) =>
    CollectionContents.loaded(items);

/// A policy that answers everything with a recognisable value.
final class _OpinionatedPolicy extends CatalogPagePolicy {
  const _OpinionatedPolicy();

  @override
  SectionLayout? layoutOf(Collection collection) =>
      const SectionLayout.grid(spanCount: 5, cellAspect: 1.5);

  @override
  CatalogContentBox? contentBoxOf(Collection collection) =>
      CatalogContentBox.cell;

  @override
  CatalogPlaceholderStyle? placeholderStyleOf(Collection collection) =>
      CatalogPlaceholderStyle.shapedWash;

  @override
  int? skeletonCountOf(Collection collection) => 9;

  @override
  String? emptyMessageOf(Collection collection, PanelStrings strings) =>
      'nothing here';

  @override
  CatalogSectionAction? actionOf(
    Collection collection,
    PanelStrings strings, {
    PanelArrangement arrangement = PanelArrangement.touch,
  }) => CatalogSectionAction(id: 'more', label: strings.clearAction);

  @override
  Object? tagOf(CollectionItem item, Collection collection) =>
      'tag:${collection.id}';

  @override
  String sectionIdOf(Collection collection) => 'section-${collection.id}';
}

void main() {
  CatalogSnapshotBuilder builder([
    CatalogPagePolicy policy = const _PlainPolicy(),
  ]) => CatalogSnapshotBuilder(policy: policy);

  CatalogSection single(
    Collection collection, {
    CatalogPagePolicy policy = const _PlainPolicy(),
  }) => builder(policy).build([collection], strings: _strings).sections.single;

  group('a loaded collection', () {
    test('becomes a loaded section of its leaves in order', () {
      final section = single(
        _collection(
          const CollectionId.set('faces'),
          title: 'Faces',
          contents: _loaded(const [
            CollectionItem.bare(_smile),
            CollectionItem.bare(_sticker),
          ]),
        ),
      );

      expect(section.id, 'CollectionId.set(faces)');
      expect(section.title, 'Faces');
      expect(section.state, CatalogSectionState.loaded);
      expect(section.leaves.map((leaf) => leaf.key), [_smile, _sticker]);
    });

    test('takes the facts of a described item from its descriptor', () {
      final section = single(
        _collection(
          const CollectionId.set('stickers'),
          contents: _loaded([
            CollectionItem.described(
              const ContentDescriptor(
                key: _sticker,
                semanticKind: SemanticKind.sticker,
                mediaForm: MediaForm.still,
                spokenName: 'wave',
              ),
            ),
          ]),
        ),
      );

      final leaf = section.leaves.single;
      expect(leaf.semanticKind, SemanticKind.sticker);
      expect(leaf.mediaForm, MediaForm.still);
      expect(leaf.spokenName, 'wave');
    });

    test('makes a glyph of a bare unicode key', () {
      final leaf = single(
        _collection(
          const CollectionId.set('faces'),
          contents: _loaded(const [CollectionItem.bare(_smile)]),
        ),
      ).leaves.single;

      expect(leaf.mediaForm, MediaForm.glyph);
      expect(leaf.semanticKind, SemanticKind.unicodeEmoji);
      expect(leaf.placeholderStyle, CatalogPlaceholderStyle.circle);
    });

    test('passes the policy message on whatever the leaf count', () {
      final section = single(
        _collection(
          const CollectionId.set('faces'),
          contents: _loaded(const [CollectionItem.bare(_smile)]),
        ),
        policy: const _OpinionatedPolicy(),
      );

      expect(section.emptyMessage, 'nothing here');
      expect(section.leaves, hasLength(1));
    });

    test('asks the policy for the empty message when it has no items', () {
      final section = single(
        _collection(
          const CollectionId.set('faces'),
          contents: _loaded(const []),
        ),
        policy: const _OpinionatedPolicy(),
      );

      expect(section.state, CatalogSectionState.loaded);
      expect(section.leaves, isEmpty);
      expect(section.emptyMessage, 'nothing here');
    });

    test('is a header alone when the policy has no empty message', () {
      final section = single(
        _collection(
          const CollectionId.set('faces'),
          contents: _loaded(const []),
        ),
      );

      expect(section.emptyMessage, isNull);
    });
  });

  group('a collection that is not loaded', () {
    test('idle and loading are a loading section of skeletons', () {
      for (final contents in [
        CollectionContents.idle,
        CollectionContents.loading,
      ]) {
        final section = single(
          _collection(const CollectionId.set('faces'), contents: contents),
        );

        expect(section.state, CatalogSectionState.loading, reason: '$contents');
        expect(section.leaves, isEmpty);
      }
    });

    test(
      'a failed first load is a failed section, with no error of its own',
      () {
        final section = single(
          _collection(
            const CollectionId.set('faces'),
            contents: const CollectionContents.failed('offline'),
          ),
        );

        expect(section.state, CatalogSectionState.failed);
        expect(section.leaves, isEmpty);
        expect(section.emptyMessage, isNull);
      },
    );

    test(
      'the policy sets how many skeletons it shows, and the empty message waits',
      () {
        final section = single(
          _collection(const CollectionId.set('faces')),
          policy: const _OpinionatedPolicy(),
        );

        expect(section.skeletonCount, 9);
        expect(section.emptyMessage, isNull);
      },
    );

    test('a loaded section carries no skeleton count', () {
      final section = single(
        _collection(
          const CollectionId.set('faces'),
          contents: _loaded(const []),
        ),
        policy: const _OpinionatedPolicy(),
      );

      expect(section.skeletonCount, isNull);
    });
  });

  group('what the policy decides', () {
    test('passes geometry, content box, stand-in and action through', () {
      final section = single(
        _collection(const CollectionId.set('s')),
        policy: const _OpinionatedPolicy(),
      );

      expect(
        section.layout,
        const SectionLayout.grid(spanCount: 5, cellAspect: 1.5),
      );
      expect(section.contentBox, CatalogContentBox.cell);
      expect(section.placeholderStyle, CatalogPlaceholderStyle.shapedWash);
      expect(
        section.action,
        CatalogSectionAction(id: 'more', label: _strings.clearAction),
      );
    });

    test('names the section by its own id and tags its leaves', () {
      final section = single(
        _collection(
          const CollectionId.set('s'),
          contents: _loaded(const [CollectionItem.bare(_smile)]),
        ),
        policy: const _OpinionatedPolicy(),
      );

      expect(section.id, 'section-CollectionId.set(s)');
      expect(section.leaves.single.tag, 'tag:CollectionId.set(s)');
    });

    test('titles recents and search results from the panel strings', () {
      final snapshot = builder().build([
        _collection(CollectionId.recent),
        _collection(const CollectionId.query('smile')),
      ], strings: _strings);

      expect(snapshot.sections[0].title, _strings.recentlyUsedTitle);
      expect(snapshot.sections[1].title, _strings.searchResultsTitle);
    });

    test('says empty search results with the panel strings', () {
      final section = single(
        _collection(
          const CollectionId.query('zzz'),
          contents: _loaded(const []),
        ),
      );

      expect(section.emptyMessage, _strings.searchEmpty);
    });
  });

  group('finding the collection behind a section', () {
    test('answers by section id', () {
      final faces = _collection(const CollectionId.set('faces'));
      final b = builder()..build([faces], strings: _strings);

      expect(b.collectionOf('CollectionId.set(faces)'), faces);
      expect(b.collectionOf('CollectionId.set(other)'), isNull);
    });

    test('answers for the last build only', () {
      final b = builder()
        ..build([_collection(const CollectionId.set('a'))], strings: _strings)
        ..build([_collection(const CollectionId.set('b'))], strings: _strings);

      expect(b.collectionOf('CollectionId.set(a)'), isNull);
      expect(b.collectionOf('CollectionId.set(b)'), isNotNull);
    });
  });

  test('keeps the collections in order', () {
    final snapshot = builder().build([
      _collection(const CollectionId.set('b')),
      _collection(const CollectionId.set('a')),
    ], strings: _strings);

    expect(snapshot.sections.map((section) => section.id), [
      'CollectionId.set(b)',
      'CollectionId.set(a)',
    ]);
  });
}

final class _PlainPolicy extends CatalogPagePolicy {
  const _PlainPolicy();
}
