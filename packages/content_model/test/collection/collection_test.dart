import 'package:content_model/content_model.dart';
import 'package:test/test.dart';

void main() {
  const a = ContentKey.document('a');
  const b = ContentKey.document('b');

  group('CollectionItem', () {
    test('bare carries a key and no descriptor', () {
      const item = CollectionItem.bare(a);

      expect(item.key, a);
      expect(item.descriptor, isNull);
    });

    test(
      'described takes its key from the descriptor, so they cannot differ',
      () {
        const descriptor = ContentDescriptor(
          key: a,
          semanticKind: SemanticKind.sticker,
        );
        final item = CollectionItem.described(descriptor);

        expect(item.key, a);
        expect(item.descriptor, descriptor);
      },
    );

    test('is a value of its key and descriptor', () {
      const descriptor = ContentDescriptor(key: a);

      expect(const CollectionItem.bare(a), const CollectionItem.bare(a));
      expect(
        const CollectionItem.bare(a).hashCode,
        const CollectionItem.bare(a).hashCode,
      );
      expect(
        CollectionItem.described(descriptor),
        CollectionItem.described(descriptor),
      );
      expect(
        CollectionItem.described(descriptor).hashCode,
        CollectionItem.described(descriptor).hashCode,
      );
      expect(const CollectionItem.bare(a), isNot(const CollectionItem.bare(b)));
    });

    test('an item with a descriptor differs from the bare item of its key', () {
      expect(
        CollectionItem.described(const ContentDescriptor(key: a)),
        isNot(const CollectionItem.bare(a)),
      );
    });

    test('described items differ when their descriptors differ', () {
      expect(
        CollectionItem.described(const ContentDescriptor(key: a)),
        isNot(
          CollectionItem.described(
            const ContentDescriptor(key: a, locked: true),
          ),
        ),
      );
    });
  });

  group('PageToken', () {
    test('is equal by its opaque value', () {
      expect(const PageToken('t'), const PageToken('t'));
      expect(const PageToken('t'), isNot(const PageToken('u')));
    });
  });

  group('CollectionFlags', () {
    test('none contains nothing and every flag contains itself', () {
      expect(CollectionFlags.none.contains(CollectionFlags.installed), isFalse);
      expect(CollectionFlags.none.contains(CollectionFlags.none), isTrue);
      for (final flag in const [
        CollectionFlags.installed,
        CollectionFlags.featured,
        CollectionFlags.official,
      ]) {
        expect(flag.contains(flag), isTrue);
        expect(CollectionFlags.none.contains(flag), isFalse);
      }
    });

    test('flags are distinct', () {
      expect(CollectionFlags.installed, isNot(CollectionFlags.featured));
      expect(CollectionFlags.featured, isNot(CollectionFlags.official));
      expect(CollectionFlags.installed, isNot(CollectionFlags.none));
    });

    test('combines with | into a set that contains each member', () {
      final both = CollectionFlags.installed | CollectionFlags.official;

      expect(both.contains(CollectionFlags.installed), isTrue);
      expect(both.contains(CollectionFlags.official), isTrue);
      expect(both.contains(CollectionFlags.featured), isFalse);
      expect(both.contains(both), isTrue);
    });

    test('a combination is equal regardless of the order it was built in', () {
      expect(
        CollectionFlags.installed | CollectionFlags.official,
        CollectionFlags.official | CollectionFlags.installed,
      );
      expect(
        CollectionFlags.installed | CollectionFlags.installed,
        CollectionFlags.installed,
      );
    });

    test('a combination does not contain a flag it merely overlaps', () {
      final both = CollectionFlags.installed | CollectionFlags.official;

      expect(CollectionFlags.installed.contains(both), isFalse);
    });
  });

  group('CollectionMetadata', () {
    test('empty has no title, no cover and no flags', () {
      // ignore: use_named_constants
      const empty = CollectionMetadata();

      expect(empty.title, isNull);
      expect(empty.cover, isNull);
      expect(empty.flags, CollectionFlags.none);
      expect(CollectionMetadata.empty, empty);
    });

    test('is a value of title, cover and flags', () {
      const metadata = CollectionMetadata(
        title: 'Cats',
        cover: a,
        flags: CollectionFlags.installed,
      );

      expect(
        metadata,
        const CollectionMetadata(
          title: 'Cats',
          cover: a,
          flags: CollectionFlags.installed,
        ),
      );
      expect(
        metadata.hashCode,
        const CollectionMetadata(
          title: 'Cats',
          cover: a,
          flags: CollectionFlags.installed,
        ).hashCode,
      );
      expect(metadata, isNot(const CollectionMetadata(title: 'Dogs')));
      expect(
        metadata,
        isNot(
          const CollectionMetadata(
            title: 'Cats',
            cover: b,
            flags: CollectionFlags.installed,
          ),
        ),
      );
      expect(
        metadata,
        isNot(const CollectionMetadata(title: 'Cats', cover: a)),
      );
    });

    test('cover is a content key, so it can be any kind of content', () {
      const metadata = CollectionMetadata(
        cover: ContentKey.unicode('\u{1F600}'),
      );

      expect(metadata.cover, const ContentKey.unicode('\u{1F600}'));
    });
  });

  group('CollectionContents', () {
    test('idle, loading and failed are distinct states', () {
      expect(CollectionContents.idle, CollectionContents.idle);
      expect(CollectionContents.loading, CollectionContents.loading);
      expect(CollectionContents.idle, isNot(CollectionContents.loading));
      expect(
        CollectionContents.idle.hashCode,
        isNot(CollectionContents.loading.hashCode),
      );
    });

    test('loaded holds its items in order and the next page token', () {
      final contents = CollectionContents.loaded(const [
        CollectionItem.bare(a),
        CollectionItem.bare(b),
      ], nextPageToken: const PageToken('2'));

      expect(contents, isA<CollectionContents$Loaded>());
      final loaded = contents as CollectionContents$Loaded;
      expect(loaded.items.map((item) => item.key), [a, b]);
      expect(loaded.nextPageToken, const PageToken('2'));
    });

    test('loaded without a token is the last page', () {
      final loaded =
          CollectionContents.loaded(const [CollectionItem.bare(a)])
              as CollectionContents$Loaded;

      expect(loaded.nextPageToken, isNull);
    });

    test('loaded with no items is a valid, empty result', () {
      final loaded =
          CollectionContents.loaded(const []) as CollectionContents$Loaded;

      expect(loaded.items, isEmpty);
    });

    test('loaded is equal by items in order and token', () {
      CollectionContents make(List<CollectionItem> items, [PageToken? token]) =>
          CollectionContents.loaded(items, nextPageToken: token);

      expect(
        make(const [CollectionItem.bare(a), CollectionItem.bare(b)]),
        make(const [CollectionItem.bare(a), CollectionItem.bare(b)]),
      );
      expect(
        make(const [CollectionItem.bare(a), CollectionItem.bare(b)]).hashCode,
        make(const [CollectionItem.bare(a), CollectionItem.bare(b)]).hashCode,
      );
      expect(
        make(const [CollectionItem.bare(a), CollectionItem.bare(b)]),
        isNot(make(const [CollectionItem.bare(b), CollectionItem.bare(a)])),
      );
      expect(
        make(const [CollectionItem.bare(a)]),
        isNot(make(const [CollectionItem.bare(a), CollectionItem.bare(b)])),
      );
      expect(
        make(const [CollectionItem.bare(a)]),
        isNot(make(const [CollectionItem.bare(a)], const PageToken('2'))),
      );
      expect(
        make(const [CollectionItem.bare(a)], const PageToken('2')),
        isNot(make(const [CollectionItem.bare(a)], const PageToken('3'))),
      );
    });

    test('loaded is not equal to any other state', () {
      final empty = CollectionContents.loaded(const []);

      expect(empty, isNot(CollectionContents.idle));
      expect(empty, isNot(CollectionContents.loading));
      expect(empty, isNot(CollectionContents.failed(StateError('x'))));
    });

    test('loaded copies its items, so the source list cannot change it', () {
      final source = <CollectionItem>[const CollectionItem.bare(a)];
      final loaded =
          CollectionContents.loaded(source) as CollectionContents$Loaded;

      source.add(const CollectionItem.bare(b));

      expect(loaded.items, hasLength(1));
    });

    test('loaded items cannot be modified', () {
      final loaded =
          CollectionContents.loaded(const [CollectionItem.bare(a)])
              as CollectionContents$Loaded;

      expect(
        () => loaded.items.add(const CollectionItem.bare(b)),
        throwsUnsupportedError,
      );
      expect(loaded.items.clear, throwsUnsupportedError);
    });

    test('failed keeps the error and stack trace it was given', () {
      final error = StateError('offline');
      final trace = StackTrace.current;
      final failed =
          CollectionContents.failed(error, trace) as CollectionContents$Failed;

      expect(failed.error, same(error));
      expect(failed.stackTrace, same(trace));
    });

    test('failed is equal by error and ignores the stack trace', () {
      final error = StateError('offline');

      expect(
        CollectionContents.failed(error),
        CollectionContents.failed(error, StackTrace.current),
      );
      expect(
        CollectionContents.failed(error).hashCode,
        CollectionContents.failed(error, StackTrace.current).hashCode,
      );
      expect(
        CollectionContents.failed(error),
        isNot(CollectionContents.failed(StateError('offline'))),
      );
    });

    test('exposes each state for exhaustive pattern matching', () {
      String describe(CollectionContents contents) => switch (contents) {
        CollectionContents$Idle() => 'idle',
        CollectionContents$Loading() => 'loading',
        CollectionContents$Loaded(:final items) => 'loaded ${items.length}',
        CollectionContents$Failed(:final error) => 'failed $error',
      };

      expect(describe(CollectionContents.idle), 'idle');
      expect(describe(CollectionContents.loading), 'loading');
      expect(
        describe(CollectionContents.loaded(const [CollectionItem.bare(a)])),
        'loaded 1',
      );
      expect(describe(const CollectionContents.failed('boom')), 'failed boom');
    });
  });

  group('Collection', () {
    test('starts idle with empty metadata when only an id is given', () {
      const collection = Collection(id: CollectionId.set('s'));

      expect(collection.id, const CollectionId.set('s'));
      expect(collection.metadata, CollectionMetadata.empty);
      expect(collection.contents, CollectionContents.idle);
    });

    test('metadata and contents are independent of each other', () {
      const withMetadata = Collection(
        id: CollectionId.set('s'),
        metadata: CollectionMetadata(title: 'Cats'),
      );
      final withContents = Collection(
        id: const CollectionId.set('s'),
        contents: CollectionContents.loaded(const [CollectionItem.bare(a)]),
      );

      expect(withMetadata.contents, CollectionContents.idle);
      expect(withContents.metadata, CollectionMetadata.empty);
    });

    test('is a value of id, metadata and contents', () {
      Collection make({
        CollectionId id = const CollectionId.set('s'),
        CollectionMetadata metadata = const CollectionMetadata(title: 'Cats'),
        CollectionContents? contents,
      }) => Collection(
        id: id,
        metadata: metadata,
        contents:
            contents ??
            CollectionContents.loaded(const [CollectionItem.bare(a)]),
      );

      expect(make(), make());
      expect(make().hashCode, make().hashCode);
      expect(make(), isNot(make(id: const CollectionId.set('t'))));
      expect(
        make(),
        isNot(make(metadata: const CollectionMetadata(title: 'Dogs'))),
      );
      expect(make(), isNot(make(contents: CollectionContents.loading)));
    });

    test('a loaded page in progress keeps its items while more are pending', () {
      // Pagination does not leave `loaded`: the next-page token is the signal
      // that more exists, and a failed further page leaves the items in place.
      final collection = Collection(
        id: CollectionId.recent,
        contents: CollectionContents.loaded(const [
          CollectionItem.bare(a),
        ], nextPageToken: const PageToken('p2')),
      );

      expect(collection.contents, isA<CollectionContents$Loaded>());
    });

    test('toString names the id and the contents state', () {
      const collection = Collection(id: CollectionId.set('s'));

      expect(collection.toString(), 'Collection(CollectionId.set(s), idle)');
    });
  });
}
