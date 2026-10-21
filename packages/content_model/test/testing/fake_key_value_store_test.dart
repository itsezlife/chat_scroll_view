import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:test/test.dart';

void main() {
  KeyValueStoreContract.run(FakeKeyValueStore.new);

  group('FakeKeyValueStore failure', () {
    const stored = StoredValue('kept', version: 1);
    late FakeKeyValueStore store;

    setUp(() async {
      store = FakeKeyValueStore();
      await store.write('ns', 'k', stored);
    });

    test('fails every call with the given exception', () async {
      final down = Exception('storage down');
      store.failure = down;

      await expectLater(store.read('ns', 'k'), throwsA(down));
      await expectLater(store.write('ns', 'k', stored), throwsA(down));
      await expectLater(store.remove('ns', 'k'), throwsA(down));
    });

    test('leaves the stored values as they were', () async {
      store.failure = Exception('storage down');
      await expectLater(
        store.write('ns', 'k', const StoredValue('lost', version: 2)),
        throwsException,
      );
      await expectLater(store.remove('ns', 'k'), throwsException);

      store.failure = null;
      expect(await store.read('ns', 'k'), stored);
    });

    test('counts only the writes that succeeded', () async {
      store.failure = Exception('storage down');
      await expectLater(store.write('ns', 'k', stored), throwsException);
      store.failure = null;
      await store.write('ns', 'k2', stored);

      expect(store.writeCount, 2);
      expect(store.entries.keys, ['ns:k', 'ns:k2']);
    });
  });
}
