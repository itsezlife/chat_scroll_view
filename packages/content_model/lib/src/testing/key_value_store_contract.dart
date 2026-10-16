import 'package:content_model/content_model.dart';
import 'package:test/test.dart';

/// The behaviour every [KeyValueStore] must have, as a test suite to run
/// against an implementation.
abstract final class KeyValueStoreContract {
  /// Runs the [KeyValueStore] contract against the stores [create] returns.
  ///
  /// [create] is called once per test and must return an empty store, so tests
  /// do not leak into each other. Run it from the test file of every adapter.
  static void run(KeyValueStore Function() create) {
    group('KeyValueStore contract', () {
      late KeyValueStore store;

      setUp(() => store = create());

      test('reads a missing value as null', () async {
        expect(await store.read('chrome', 'missing'), isNull);
      });

      test('reads back what was written, with its version', () async {
        await store.write(
          'chrome',
          'recents',
          const StoredValue('{"a":1}', version: 3),
        );

        expect(
          await store.read('chrome', 'recents'),
          const StoredValue('{"a":1}', version: 3),
        );
      });

      test('replaces the earlier value, version included', () async {
        await store.write('chrome', 'k', const StoredValue('one', version: 1));
        await store.write('chrome', 'k', const StoredValue('two', version: 2));

        expect(
          await store.read('chrome', 'k'),
          const StoredValue('two', version: 2),
        );
      });

      test('keeps text exactly as written', () async {
        const awkward = StoredValue(
          '\u{1F44D}\u{1F3FB} line\nbreak "quoted" \u0000 ',
          version: 1,
        );
        const empty = StoredValue('', version: 1);

        await store.write('chrome', 'awkward', awkward);
        await store.write('chrome', 'empty', empty);

        expect(await store.read('chrome', 'awkward'), awkward);
        expect(await store.read('chrome', 'empty'), empty);
      });

      test('keeps namespaces apart', () async {
        await store.write('one', 'k', const StoredValue('a', version: 1));
        await store.write('two', 'k', const StoredValue('b', version: 1));

        expect(
          await store.read('one', 'k'),
          const StoredValue('a', version: 1),
        );
        expect(
          await store.read('two', 'k'),
          const StoredValue('b', version: 1),
        );
      });

      test('keeps keys apart', () async {
        await store.write('ns', 'a', const StoredValue('1', version: 1));

        expect(await store.read('ns', 'b'), isNull);
      });

      test('does not confuse a namespace and key that join alike', () async {
        await store.write('a.b', 'c', const StoredValue('x', version: 1));

        expect(await store.read('a', 'b.c'), isNull);
        expect(await store.read('a.b', 'c'), isNotNull);
      });

      test('removes a value and only that value', () async {
        await store.write('ns', 'a', const StoredValue('1', version: 1));
        await store.write('ns', 'b', const StoredValue('2', version: 1));

        await store.remove('ns', 'a');

        expect(await store.read('ns', 'a'), isNull);
        expect(await store.read('ns', 'b'), const StoredValue('2', version: 1));
      });

      test('treats removing a missing value as success', () async {
        await store.remove('ns', 'never-written');

        expect(await store.read('ns', 'never-written'), isNull);
      });

      test(
        'accepts letters, digits, underscore, dot and dash in names',
        () async {
          await store.write(
            'Pkg_1.v-2',
            'Key_9.x-y',
            const StoredValue('v', version: 1),
          );

          expect(await store.read('Pkg_1.v-2', 'Key_9.x-y'), isNotNull);
        },
      );

      group('rejects a name that is empty or has another character', () {
        const bad = ['', 'a:b', 'a b', 'a/b', 'café'];
        const value = StoredValue('v', version: 1);

        for (final name in bad) {
          test('"$name"', () async {
            await expectLater(store.read(name, 'k'), throwsArgumentError);
            await expectLater(store.read('ns', name), throwsArgumentError);
            await expectLater(
              store.write(name, 'k', value),
              throwsArgumentError,
            );
            await expectLater(
              store.write('ns', name, value),
              throwsArgumentError,
            );
            await expectLater(store.remove(name, 'k'), throwsArgumentError);
            await expectLater(store.remove('ns', name), throwsArgumentError);
          });
        }
      });
    });
  }
}
