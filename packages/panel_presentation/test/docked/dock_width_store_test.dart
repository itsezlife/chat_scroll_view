import 'dart:async';

import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_presentation/panel_presentation.dart';

void main() {
  late FakeKeyValueStore kv;

  setUp(() => kv = FakeKeyValueStore());

  Future<DockWidthStore> open() => DockWidthStore.open(kv);

  test('a fresh store knows no width', () async {
    expect((await open()).width, isNull);
  });

  group('recording', () {
    test(
      'keeps the last width, wider or narrower than the one before',
      () async {
        final store = await open();

        await store.record(340);
        expect(store.width, 340);
        await store.record(300);
        expect(store.width, 300);
      },
    );

    test('survives a reopen over the same key-value store', () async {
      await (await open()).record(321.5);

      expect((await open()).width, 321.5);
    });

    test('ignores what is not a width', () async {
      final store = await open();

      await store.record(0);
      await store.record(-4);
      await store.record(double.nan);
      await store.record(double.infinity);

      expect(store.width, isNull);
      expect(kv.writeCount, 0);
    });

    test('a width that is already kept is not written again', () async {
      final store = await open();
      await store.record(340);
      final writes = kv.writeCount;

      await store.record(340);

      expect(kv.writeCount, writes);
    });
  });

  group('stored data', () {
    for (final (name, stored) in [
      ('of another version', const StoredValue('340', version: 99)),
      ('that is not a number', const StoredValue('wide', version: 1)),
      ('that is not positive', const StoredValue('-3', version: 1)),
    ]) {
      test('a value $name is not trusted', () async {
        await kv.write(DockWidthStore.namespace, 'dockWidth', stored);

        expect((await open()).width, isNull);
      });
    }
  });

  test(
    'a failed write keeps the width in memory and reaches the zone',
    () async {
      final store = await open();
      kv.failure = Exception('disk full');
      final errors = <Object>[];

      await runZonedGuarded(
        () => store.record(340),
        (error, stack) => errors.add(error),
      );

      expect(store.width, 340);
      expect(errors, hasLength(1));
    },
  );
}
