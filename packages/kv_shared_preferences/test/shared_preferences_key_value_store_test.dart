import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kv_shared_preferences/kv_shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

/// An in-memory platform whose storage can be made unreachable.
base class _SwitchablePlatform extends InMemorySharedPreferencesAsync {
  _SwitchablePlatform({Map<String, Object> data = const {}})
    : super.withData(data);

  bool reachable = true;

  /// The string stored under [key], read without the store under test.
  Future<String?> dataFor(String key) =>
      super.getString(key, const SharedPreferencesOptions());

  Future<T> _through<T>(Future<T> Function() call) =>
      reachable ? call() : Future<T>.error(StateError('storage unreachable'));

  @override
  Future<String?> getString(String key, SharedPreferencesOptions options) =>
      _through(() => super.getString(key, options));

  @override
  Future<bool> setString(
    String key,
    String value,
    SharedPreferencesOptions options,
  ) => _through(() => super.setString(key, value, options));

  @override
  Future<Set<String>> getKeys(
    GetPreferencesParameters parameters,
    SharedPreferencesOptions options,
  ) => _through(() => super.getKeys(parameters, options));

  @override
  Future<bool> clear(
    ClearPreferencesParameters parameters,
    SharedPreferencesOptions options,
  ) => _through(() => super.clear(parameters, options));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _SwitchablePlatform platform;

  Future<KeyValueStore> open({Map<String, Object> data = const {}}) {
    platform = _SwitchablePlatform(data: data);
    SharedPreferencesAsyncPlatform.instance = platform;
    return SharedPreferencesKeyValueStore.open();
  }

  group('contract', () {
    late KeyValueStore store;

    setUp(() async => store = await open());

    runKeyValueStoreContract(() => store);
  });

  group('persistence', () {
    test('a store opened later reads what an earlier one wrote', () async {
      final first = await open();
      await first.write('chrome', 'k', const StoredValue('kept', version: 2));

      SharedPreferencesAsyncPlatform.instance = platform;
      final second = await SharedPreferencesKeyValueStore.open();

      expect(
        await second.read('chrome', 'k'),
        const StoredValue('kept', version: 2),
      );
    });

    test('stores version and text as one platform string', () async {
      final store = await open();

      await store.write('chrome', 'k', const StoredValue('a:b', version: 7));

      expect(await platform.dataFor('chrome:k'), '7:a:b');
    });

    test('keeps a negative version', () async {
      final store = await open();

      await store.write('ns', 'k', const StoredValue('x', version: -1));

      expect(await store.read('ns', 'k'), const StoredValue('x', version: -1));
    });
  });

  group('foreign data', () {
    test('reads an entry that is not "version:text" as missing', () async {
      final store = await open(
        data: {'ns:bare': 'no separator', 'ns:word': 'v1:text'},
      );

      expect(await store.read('ns', 'bare'), isNull);
      expect(await store.read('ns', 'word'), isNull);
    });

    test('removes only the entry named, not the host\'s own keys', () async {
      final store = await open(data: {'theme': 'dark', 'ns:other': '1:x'});
      await store.write('ns', 'k', const StoredValue('v', version: 1));

      await store.remove('ns', 'k');

      expect(await platform.dataFor('theme'), 'dark');
      expect(await platform.dataFor('ns:other'), '1:x');
      expect(await platform.dataFor('ns:k'), isNull);
    });
  });

  group('unreachable storage', () {
    test('fails to open', () async {
      platform = _SwitchablePlatform()..reachable = false;
      SharedPreferencesAsyncPlatform.instance = platform;

      await expectLater(
        SharedPreferencesKeyValueStore.open(),
        throwsStateError,
      );
    });

    test('fails every call once the storage goes away', () async {
      final store = await open();
      platform.reachable = false;
      const value = StoredValue('v', version: 1);

      await expectLater(store.read('ns', 'k'), throwsStateError);
      await expectLater(store.write('ns', 'k', value), throwsStateError);
      await expectLater(store.remove('ns', 'k'), throwsStateError);
    });

    test(
      'a failed write or remove leaves the stored value as it was',
      () async {
        final store = await open();
        await store.write('ns', 'k', const StoredValue('old', version: 1));
        platform.reachable = false;

        await expectLater(
          store.write('ns', 'k', const StoredValue('new', version: 2)),
          throwsStateError,
        );
        await expectLater(store.remove('ns', 'k'), throwsStateError);
        platform.reachable = true;

        expect(
          await store.read('ns', 'k'),
          const StoredValue('old', version: 1),
        );
      },
    );
  });
}
