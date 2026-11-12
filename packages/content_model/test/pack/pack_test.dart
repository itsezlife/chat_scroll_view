import 'package:content_model/content_model.dart';
import 'package:test/test.dart';

void main() {
  const cat = ContentDescriptor(
    key: ContentKey.document('cat'),
    semanticKind: SemanticKind.sticker,
    pack: PackId('cats'),
  );
  const kitten = ContentDescriptor(
    key: ContentKey.document('kitten'),
    semanticKind: SemanticKind.sticker,
    pack: PackId('cats'),
  );

  Pack cats({String title = 'Cats', bool official = false}) => Pack(
    id: const PackId('cats'),
    kind: PackKind.stickers,
    title: title,
    items: const [cat, kitten],
    cover: kitten.key,
    official: official,
  );

  group('PackKind', () {
    test('decodes every written value back to itself', () {
      for (final kind in PackKind.values) {
        expect(PackKind.fromValue(kind.value), kind);
      }
    });

    test('has stable written values', () {
      expect(PackKind.stickers.value, 'stickers');
      expect(PackKind.masks.value, 'masks');
      expect(PackKind.emoji.value, 'emoji');
    });

    test('rejects an unknown value and null without a fallback', () {
      expect(() => PackKind.fromValue('photos'), throwsArgumentError);
      expect(() => PackKind.fromValue(null), throwsArgumentError);
      expect(
        PackKind.fromValue(null, fallback: PackKind.emoji),
        PackKind.emoji,
      );
    });

    test('names the semantic kind of what it holds', () {
      expect(PackKind.stickers.itemKind, SemanticKind.sticker);
      expect(PackKind.masks.itemKind, SemanticKind.mask);
      expect(PackKind.emoji.itemKind, SemanticKind.customEmoji);
    });
  });

  group('Pack', () {
    test('counts its items', () {
      expect(cats().count, 2);
    });

    test('keeps its items unmodifiable', () {
      expect(() => cats().items.add(cat), throwsUnsupportedError);
    });

    test('is a value of all its fields', () {
      expect(cats(), cats());
      expect(cats().hashCode, cats().hashCode);
      expect(cats(), isNot(cats(title: 'Kittens')));
      expect(cats(), isNot(cats(official: true)));
    });

    test('is listed as the set collection of its id', () {
      expect(cats().collectionId, const CollectionId.set('cats'));
    });

    test('projects to a loaded collection of its described items', () {
      final collection = cats(official: true).collection;

      expect(collection.id, const CollectionId.set('cats'));
      expect(collection.metadata.title, 'Cats');
      expect(collection.metadata.cover, kitten.key);
      expect(
        collection.metadata.flags.contains(CollectionFlags.official),
        isTrue,
      );
      expect(
        collection.contents,
        CollectionContents.loaded([
          CollectionItem.described(cat),
          CollectionItem.described(kitten),
        ]),
      );
    });
  });
}
