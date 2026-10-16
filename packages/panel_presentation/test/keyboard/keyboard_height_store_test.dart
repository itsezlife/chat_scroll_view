import 'dart:async';

import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_presentation/panel_presentation.dart';

void main() {
  late FakeKeyValueStore kv;

  setUp(() => kv = FakeKeyValueStore());

  Future<KeyboardHeightStore> open() => KeyboardHeightStore.open(kv);

  group('a fresh store', () {
    test('knows no height in either orientation', () async {
      final store = await open();
      expect(store.heightFor(PanelOrientation.portrait), isNull);
      expect(store.heightFor(PanelOrientation.landscape), isNull);
    });
  });

  group('recording', () {
    test('keeps portrait and landscape apart', () async {
      final store = await open();
      await store.record(PanelOrientation.portrait, 310);
      await store.record(PanelOrientation.landscape, 200);
      expect(store.heightFor(PanelOrientation.portrait), 310);
      expect(store.heightFor(PanelOrientation.landscape), 200);
    });

    test('survives a reopen over the same key-value store', () async {
      final first = await open();
      await first.record(PanelOrientation.portrait, 310.5);
      await first.record(PanelOrientation.landscape, 190);

      final second = await open();
      expect(second.heightFor(PanelOrientation.portrait), 310.5);
      expect(second.heightFor(PanelOrientation.landscape), 190);
    });

    test('ignores a height below the sanity floor', () async {
      final store = await open();
      await store.record(PanelOrientation.portrait, 59);
      await store.record(PanelOrientation.portrait, 179.9);
      expect(store.heightFor(PanelOrientation.portrait), isNull);
      expect(kv.writeCount, 0);
    });

    test('accepts a height exactly at the floor', () async {
      final store = await open();
      await store.record(PanelOrientation.portrait, 180);
      expect(store.heightFor(PanelOrientation.portrait), 180);
    });

    test('ignores a height that is not a finite number', () async {
      final store = await open();
      await store.record(PanelOrientation.portrait, double.nan);
      await store.record(PanelOrientation.portrait, double.infinity);
      expect(store.heightFor(PanelOrientation.portrait), isNull);
    });

    test('a taller keyboard replaces the stored height', () async {
      final store = await open();
      await store.record(PanelOrientation.portrait, 300);
      await store.record(PanelOrientation.portrait, 340);
      expect(store.heightFor(PanelOrientation.portrait), 340);
    });

    test('one shorter sample does not lower a sane height', () async {
      final store = await open();
      await store.record(PanelOrientation.portrait, 310);
      await store.record(PanelOrientation.portrait, 250);
      expect(store.heightFor(PanelOrientation.portrait), 310);
    });

    test('a sample that is not taller is not a change', () async {
      final store = await open();
      await store.record(PanelOrientation.portrait, 310);
      final writes = kv.writeCount;
      await store.record(PanelOrientation.portrait, 309.5);
      await store.record(PanelOrientation.portrait, 310);
      await store.record(PanelOrientation.portrait, 310);
      expect(store.heightFor(PanelOrientation.portrait), 310);
      expect(kv.writeCount, writes);
    });
  });

  group('stored data', () {
    test('a value written below the floor is not trusted', () async {
      await kv.write(
        KeyboardHeightStore.namespace,
        'height.portrait',
        const StoredValue('59', version: 1),
      );
      final store = await open();
      expect(store.heightFor(PanelOrientation.portrait), isNull);
    });

    test('a value of an unknown version is not trusted', () async {
      await kv.write(
        KeyboardHeightStore.namespace,
        'height.portrait',
        const StoredValue('310', version: 99),
      );
      final store = await open();
      expect(store.heightFor(PanelOrientation.portrait), isNull);
    });

    test('a value that is not a number is not trusted', () async {
      await kv.write(
        KeyboardHeightStore.namespace,
        'height.portrait',
        const StoredValue('tall', version: 1),
      );
      final store = await open();
      expect(store.heightFor(PanelOrientation.portrait), isNull);
    });
  });

  group('when persisting fails', () {
    test(
      'keeps the height in memory and reports the error to the zone',
      () async {
        final store = await open();
        kv.failure = Exception('disk full');
        final errors = <Object>[];
        await runZonedGuarded(
          () => store.record(PanelOrientation.portrait, 310),
          (error, stack) => errors.add(error),
        );
        expect(store.heightFor(PanelOrientation.portrait), 310);
        expect(errors, hasLength(1));
      },
    );
  });
}
