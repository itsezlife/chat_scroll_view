import 'package:content_model/content_model.dart';
import 'package:test/test.dart';

void main() {
  group('equality', () {
    test('ids of one variant are equal by value and hash alike', () {
      expect(const CollectionId.set('s'), const CollectionId.set('s'));
      expect(
        const CollectionId.set('s').hashCode,
        const CollectionId.set('s').hashCode,
      );
      expect(const CollectionId.query('cat'), const CollectionId.query('cat'));
      expect(
        const CollectionId.category('people'),
        const CollectionId.category('people'),
      );
      expect(CollectionId.recent, CollectionId.recent);
      expect(CollectionId.recent.hashCode, CollectionId.recent.hashCode);
    });

    test('the same text under different variants is not the same id', () {
      const ids = <CollectionId>[
        CollectionId.set('x'),
        CollectionId.query('x'),
        CollectionId.category('x'),
      ];

      expect(ids.toSet(), hasLength(3));
    });

    test('well-known lists are three distinct ids', () {
      expect({
        CollectionId.recent,
        CollectionId.faved,
        CollectionId.saved,
      }, hasLength(3));
      expect(CollectionId.recent, isNot(CollectionId.faved));
    });

    test('a well-known id is never a set, query or category of its name', () {
      expect(CollectionId.recent, isNot(const CollectionId.set('recent')));
      expect(CollectionId.recent, isNot(const CollectionId.query('recent')));
      expect(CollectionId.recent, isNot(const CollectionId.category('recent')));
    });

    test('the empty query is a valid id and differs from every other', () {
      expect(const CollectionId.query(''), const CollectionId.query(''));
      expect(const CollectionId.query(''), isNot(const CollectionId.set('a')));
    });

    test('query text is kept exactly, never normalised', () {
      expect(
        const CollectionId.query('Smile '),
        isNot(const CollectionId.query('smile')),
      );
    });
  });

  group('construction', () {
    test('rejects an empty set or category id', () {
      final empty = StringBuffer().toString();

      expect(() => CollectionId.set(empty), throwsA(isA<AssertionError>()));
      expect(
        () => CollectionId.category(empty),
        throwsA(isA<AssertionError>()),
      );
    });

    test('exposes each variant for exhaustive pattern matching', () {
      String describe(CollectionId id) => switch (id) {
        CollectionId$Set(:final id) => 'set $id',
        CollectionId$WellKnown(:final list) => 'list ${list.name}',
        CollectionId$Query(:final text) => 'query "$text"',
        CollectionId$Category(:final id) => 'category $id',
      };

      expect(describe(const CollectionId.set('a')), 'set a');
      expect(describe(CollectionId.recent), 'list recent');
      expect(describe(CollectionId.faved), 'list faved');
      expect(describe(CollectionId.saved), 'list saved');
      expect(describe(const CollectionId.query('q')), 'query "q"');
      expect(describe(const CollectionId.category('c')), 'category c');
    });
  });

  test('toString names the variant and its payload', () {
    expect(const CollectionId.set('a').toString(), 'CollectionId.set(a)');
    expect(CollectionId.recent.toString(), 'CollectionId.recent');
    expect(CollectionId.saved.toString(), 'CollectionId.saved');
    expect(const CollectionId.query('q').toString(), 'CollectionId.query(q)');
    expect(
      const CollectionId.category('c').toString(),
      'CollectionId.category(c)',
    );
  });
}
