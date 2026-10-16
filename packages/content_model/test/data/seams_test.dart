import 'package:content_model/content_model.dart';
import 'package:listen/listen.dart';
import 'package:test/test.dart';

// The seams are interfaces a host implements with nothing but the public
// barrel. These stand-ins prove each one can be, and pin the value types the
// seams introduce.

class _CollectionSource implements CollectionSource {
  @override
  final ValueNotifier<List<Collection>> collections = ValueNotifier(
    <Collection>[],
  );

  @override
  Future<void> load(CollectionId id) async {}

  @override
  Future<void> loadMore(CollectionId id) async {}

  @override
  void dispose() => collections.dispose();
}

class _SearchSource implements SearchSource {
  @override
  final ValueNotifier<Collection> results = ValueNotifier(
    const Collection(id: CollectionId.query('')),
  );

  @override
  Future<void> search(String query) async {}

  @override
  Future<void> loadMore() async {}

  @override
  void dispose() => results.dispose();
}

class _RecentsStore implements RecentsStore {
  final _changes = ChangeNotifier();

  @override
  Listenable get changes => _changes;

  @override
  List<ContentKey> recents(SemanticKind kind) => const [];

  @override
  Future<void> record(
    ContentKey key, {
    required SemanticKind kind,
    PickSource source = PickSource.collection,
  }) async {}

  @override
  Future<void> remove(ContentKey key, {required SemanticKind kind}) async {}

  @override
  Future<void> clear({SemanticKind? kind}) async {}

  @override
  void dispose() => _changes.dispose();
}

class _PreferenceStore implements PreferenceStore {
  final _changes = ChangeNotifier();

  @override
  Listenable get changes => _changes;

  @override
  ContentKey$Unicode? preferredVariant(ContentKey$Unicode base) => null;

  @override
  Future<void> setPreferredVariant(
    ContentKey$Unicode base,
    ContentKey$Unicode? variant,
  ) async {}

  @override
  String? get selectedPageId => null;

  @override
  Future<void> setSelectedPageId(String? id) async {}

  @override
  bool get dockPreferred => false;

  @override
  Future<void> setDockPreferred({required bool preferred}) async {}

  @override
  void dispose() => _changes.dispose();
}

class _KeywordSource implements KeywordSource {
  final _changes = ChangeNotifier();

  @override
  Listenable get changes => _changes;

  @override
  Future<KeywordPack?> pack(String language) async => null;

  @override
  void dispose() => _changes.dispose();
}

class _GlyphSupport implements GlyphSupport {
  final _changes = ChangeNotifier();

  @override
  Listenable get changes => _changes;

  @override
  String? get artVersion => null;

  @override
  bool supports(ContentKey$Unicode key) => true;

  @override
  void dispose() => _changes.dispose();
}

class _KeyValueStore implements KeyValueStore {
  @override
  Future<StoredValue?> read(String namespace, String key) async => null;

  @override
  Future<void> write(String namespace, String key, StoredValue value) async {}

  @override
  Future<void> remove(String namespace, String key) async {}
}

class _ContentResolver implements ContentResolver {
  @override
  Future<Map<ContentKey, ContentDescriptor>> resolve(
    Iterable<ContentKey> keys,
  ) async => const {};
}

void main() {
  test('every seam can be implemented from the public barrel alone', () {
    final seams = <Object>[
      _CollectionSource(),
      _SearchSource(),
      _RecentsStore(),
      _PreferenceStore(),
      _KeywordSource(),
      _GlyphSupport(),
      _KeyValueStore(),
      _ContentResolver(),
    ];
    expect(seams, hasLength(8));
  });

  group('StoredValue', () {
    test('is equal to a value with the same text and version', () {
      expect(
        const StoredValue('{"a":1}', version: 2),
        const StoredValue('{"a":1}', version: 2),
      );
      expect(
        const StoredValue('x', version: 1),
        isNot(const StoredValue('x', version: 2)),
      );
      expect(
        const StoredValue('x', version: 1).hashCode,
        const StoredValue('x', version: 1).hashCode,
      );
    });
  });

  group('KeywordPack', () {
    test('copies its keywords so later changes to the input do not leak', () {
      const key = ContentKey.unicode('\u{1F44D}');
      final words = ['thumbs', 'up'];
      final input = {key: words};
      final pack = KeywordPack(language: 'en', version: 3, keywords: input);

      words.add('like');
      input.clear();

      expect(pack.keywords[key], ['thumbs', 'up']);
      expect(pack.keywords.clear, throwsUnsupportedError);
      expect(() => pack.keywords[key]!.add('x'), throwsUnsupportedError);
      expect(pack.language, 'en');
      expect(pack.version, 3);
    });
  });
}
