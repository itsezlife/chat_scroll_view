/// Which glyphs the system cannot draw: cells rendered identical to a
/// missing-glyph reference, or not rendered at all; what is persisted of that
/// and when it is trusted again.
///
/// **Seam:** `MissingGlyphProbe` fed cell pixels the way the bake pass feeds
/// them, with a `FakeKeyValueStore` and an art version producer the test
/// answers by hand. Pixels are plain bytes, so nothing needs a rasteriser or a
/// font.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:emoji_data/emoji_data.dart';
import 'package:test/test.dart';

const _reference = 'REF';

Uint8List _art(int seed) =>
    Uint8List.fromList([for (var i = 0; i < 32; i++) (seed * 7 + i) & 0xFF]);

final Uint8List _tofu = _art(99);
final Uint8List _blank = Uint8List(32);

ContentKey$Unicode _key(String glyph) => ContentKey$Unicode(glyph);

void main() {
  late FakeKeyValueStore store;

  setUp(() => store = FakeKeyValueStore());

  MissingGlyphProbe probe(
    List<String> glyphs, {
    String artVersion = 'art-1',
    Future<String> Function()? producer,
  }) {
    final result = MissingGlyphProbe(
      glyphs: glyphs,
      references: const [_reference],
      store: store,
      artVersion: producer ?? () async => artVersion,
    );
    addTearDown(result.dispose);
    return result;
  }

  /// Observes a finished probe's worth of evidence and waits for it to settle.
  Future<MissingGlyphProbe> observed(
    List<String> glyphs, {
    String artVersion = 'art-1',
    Map<String, Uint8List> cells = const {},
  }) async {
    final result = probe(glyphs, artVersion: artVersion);
    await result.start();
    result.observe(_reference, _tofu);
    for (final glyph in glyphs) {
      result.observe(glyph, cells[glyph] ?? _art(glyph.codeUnitAt(0)));
    }
    await result.completed;
    return result;
  }

  group('verdicts', () {
    test(
      'a glyph drawn like the missing-glyph reference is unsupported',
      () async {
        final subject = await observed(['a', 'b'], cells: {'b': _tofu});

        expect(subject.supports(_key('a')), isTrue);
        expect(subject.supports(_key('b')), isFalse);
      },
    );

    test(
      'a glyph that drew nothing is unsupported, whatever the reference',
      () {
        final subject = probe(['a'])..observe('a', _blank);

        expect(subject.verdictOf('a'), isFalse);
      },
    );

    group('with several references (a system that draws one as nothing and '
        'another as its box)', () {
      MissingGlyphProbe twoReferences() {
        final result = MissingGlyphProbe(
          glyphs: const ['a', 'b'],
          references: const ['NONE', 'BOX'],
          store: store,
          artVersion: () async => 'art-1',
        );
        addTearDown(result.dispose);
        return result;
      }

      test('a glyph drawn like any of them is unsupported, once all are '
          'seen', () {
        final subject = twoReferences()
          ..observe('NONE', _blank)
          ..observe('a', _art(1))
          ..observe('b', _tofu);
        expect(subject.verdictOf('b'), isNull, reason: 'BOX not seen yet');
        expect(subject.pendingReferences, ['BOX']);

        subject.observe('BOX', _tofu);

        expect(subject.verdictOf('a'), isTrue);
        expect(subject.verdictOf('b'), isFalse);
        expect(subject.pendingReferences, isEmpty);
      });

      test('a record taken against other references is not trusted', () async {
        final first = probe(['a', 'b']);
        await first.start();
        first
          ..observe(_reference, _blank)
          ..observe('a', _art(1))
          ..observe('b', _tofu);
        await first.completed;

        final second = twoReferences();
        await second.start();

        expect(second.verdictOf('b'), isNull);
        expect(second.pendingReferences, ['NONE', 'BOX']);
      });
    });

    test('the default references include a private-use character no font '
        'draws, besides the noncharacter some systems draw as nothing', () {
      expect(defaultMissingGlyphReferences, contains('\u{10FFFF}'));
      expect(defaultMissingGlyphReferences, contains('\u{F0000}'));
    });

    test('a glyph is not judged before the reference has been seen', () {
      final subject = probe(['a'])..observe('a', _tofu);
      expect(subject.verdictOf('a'), isNull);

      subject.observe(_reference, _tofu);
      expect(subject.verdictOf('a'), isFalse);
    });

    test('a glyph not yet observed has no verdict and is shown', () async {
      final subject = probe(['a', 'b']);
      await subject.start();
      subject
        ..observe(_reference, _tofu)
        ..observe('a', _art(1));

      expect(subject.verdictOf('b'), isNull);
      expect(subject.verdictOf('not planned'), isNull);
      expect(subject.supports(_key('b')), isTrue);
    });

    test('it asks for what it lacks and nothing it already has', () {
      final subject = probe(['a', 'b']);
      expect(subject.pendingReferences, [_reference]);
      expect(subject.pendingGlyphs, ['a', 'b']);
      expect(subject.wants('a'), isTrue);
      expect(subject.wants('not planned'), isFalse);

      subject
        ..observe(_reference, _tofu)
        ..observe('a', _art(1));

      expect(subject.pendingReferences, isEmpty);
      expect(subject.pendingGlyphs, ['b']);
      expect(subject.wants('a'), isFalse);
      expect(subject.wants('b'), isTrue);
    });

    test('the unsupported glyphs are listed as the evidence stands', () {
      final subject = probe(['a', 'b', 'c'])
        ..observe(_reference, _tofu)
        ..observe('a', _art(1))
        ..observe('b', _tofu)
        ..observe('c', _blank);

      expect(subject.unsupported, unorderedEquals(['b', 'c']));
    });
  });

  group('a system that draws no emoji at all', () {
    final many = [for (var i = 0; i < 20; i++) 'g$i'];

    test(
      'is not believed: nothing is hidden and nothing is persisted',
      () async {
        // Fonts that have not loaded yet draw every glyph as the reference.
        final subject = probe(many);
        await subject.start();
        subject.observe(_reference, _tofu);
        for (final glyph in many) {
          subject.observe(glyph, _tofu);
        }
        await subject.completed;

        expect(subject.supports(_key('g0')), isTrue);
        expect(subject.unsupported, isEmpty);
        expect(store.writeCount, 0);
      },
    );

    test('does not hide the one glyph a mostly working system lacks', () async {
      final subject = probe(many);
      await subject.start();
      subject.observe(_reference, _tofu);
      for (final glyph in many) {
        subject.observe(glyph, glyph == 'g3' ? _tofu : _art(glyph.length));
      }
      await subject.completed;

      expect(subject.supports(_key('g3')), isFalse);
      expect(subject.supports(_key('g4')), isTrue);
    });
  });

  group('publishing', () {
    test('holds the answers back until the art version is known', () async {
      final version = Completer<String>();
      final subject = probe(['a'], producer: () => version.future);
      var signals = 0;
      subject.changes.addListener(() => signals++);

      subject
        ..observe(_reference, _tofu)
        ..observe('a', _tofu);
      await pumpEventQueue();
      expect(subject.supports(_key('a')), isTrue);
      expect(signals, 0);

      version.complete('art-1');
      await pumpEventQueue();
      expect(subject.supports(_key('a')), isFalse);
      expect(subject.artVersion, 'art-1');
      expect(signals, 1);
    });

    test('a strip of observations is one signal; seeing art is none', () async {
      final subject = probe(['a', 'b', 'c']);
      await subject.start();
      var signals = 0;
      subject.changes.addListener(() => signals++);

      subject
        ..observe(_reference, _tofu)
        ..observe('a', _art(1))
        ..observe('b', _tofu)
        ..observe('c', _tofu);
      await pumpEventQueue();

      expect(signals, 1);

      subject.observe('a', _art(2));
      await pumpEventQueue();
      expect(signals, 1, reason: 'nothing new was hidden');
    });

    test(
      'a failing art version producer still lets verdicts be published',
      () async {
        final subject = probe([
          'a',
        ], producer: () async => throw StateError('x'));
        subject
          ..observe(_reference, _tofu)
          ..observe('a', _tofu);
        await pumpEventQueue();

        expect(subject.supports(_key('a')), isFalse);
        expect(subject.artVersion, isNull);
        await expectLater(subject.artVersionReady(), throwsStateError);
        expect(store.writeCount, 0, reason: 'nothing to key the record on');
      },
    );

    test('the art version producer runs once however it is asked', () async {
      var runs = 0;
      final subject = probe(
        ['a'],
        producer: () async {
          runs++;
          return 'art-1';
        },
      );

      expect(await subject.artVersionReady(), 'art-1');
      subject.observe('a', _art(1));
      await subject.start();
      expect(await subject.artVersionReady(), 'art-1');

      expect(runs, 1);
    });
  });

  group('disposal in flight', () {
    test('fails the art version with a defined error instead of a null '
        'check', () async {
      final version = Completer<String>();
      final subject = probe(['a'], producer: () => version.future);
      final asked = subject.artVersionReady();
      final failed = expectLater(asked, throwsStateError);

      subject.dispose();
      version.complete('art-1');

      await failed;
      expect(subject.artVersion, isNull);
      await expectLater(subject.artVersionReady(), throwsStateError);
    });

    test(
      'completes `completed` without claiming the probe is complete',
      () async {
        final subject = probe(['a'])..observe('a', _art(1));

        subject.dispose();

        await subject.completed.timeout(const Duration(seconds: 1));
        expect(subject.isComplete, isFalse);
      },
    );

    test('completes a `completed` that was already being awaited', () async {
      final subject = probe(['a', 'b']);
      final waiting = subject.completed;

      subject.dispose();

      await waiting.timeout(const Duration(seconds: 1));
    });

    test(
      'a write that finishes after disposal does not complete twice',
      () async {
        final subject = probe(['a']);
        await subject.start();
        subject
          ..observe(_reference, _tofu)
          ..observe('a', _art(1))
          ..dispose();

        await pumpEventQueue();
        await subject.completed;
      },
    );
  });

  group('persistence', () {
    test('writes one record once every glyph has a verdict', () async {
      await observed(['a', 'b'], cells: {'b': _tofu});

      expect(store.writeCount, 1);
      final stored = store.entries['emoji_data:glyph_probe']!;
      expect(stored.version, MissingGlyphProbe.recordVersion);
    });

    test('does not write before the probe is complete', () async {
      final subject = probe(['a', 'b']);
      await subject.start();
      subject
        ..observe(_reference, _tofu)
        ..observe('a', _art(1));
      await pumpEventQueue();

      expect(store.writeCount, 0);
      expect(subject.isComplete, isFalse);
    });

    test('a later launch under the same art version has the verdicts without '
        'observing anything', () async {
      await observed(['a', 'b'], cells: {'b': _tofu});

      final later = probe(['a', 'b']);
      await later.completed;

      expect(later.artVersion, 'art-1');
      expect(later.supports(_key('a')), isTrue);
      expect(later.supports(_key('b')), isFalse);
      expect(later.pendingReferences, isEmpty);
      expect(later.wants('a'), isFalse);
      expect(store.writeCount, 1, reason: 'nothing new to save');
    });

    test('a restore is one signal with the art version', () async {
      await observed(['a', 'b'], cells: {'b': _tofu});
      final later = probe(['a', 'b']);
      var signals = 0;
      later.changes.addListener(() => signals++);

      await later.completed;
      await pumpEventQueue();

      expect(signals, 1);
    });

    test(
      'verdicts taken under another art version are ignored and replaced',
      () async {
        await observed(['a', 'b'], cells: {'b': _tofu});

        final later = probe(['a', 'b'], artVersion: 'art-2');
        await later.start();

        expect(later.supports(_key('b')), isTrue);
        expect(later.isComplete, isFalse);
        expect(later.pendingReferences, [_reference]);
        expect(later.wants('a'), isTrue);

        later
          ..observe(_reference, _tofu)
          ..observe('a', _tofu)
          ..observe('b', _art(5));
        await later.completed;

        expect(later.supports(_key('a')), isFalse);
        expect(later.supports(_key('b')), isTrue);
        expect(store.writeCount, 2);
      },
    );

    test('keeps its verdicts and probes only a glyph added since', () async {
      await observed(['a', 'b'], cells: {'b': _tofu});

      final later = probe(['a', 'b', 'c']);
      await later.start();

      expect(later.isComplete, isFalse);
      expect(later.supports(_key('b')), isFalse);
      expect(later.pendingGlyphs, ['c']);
      expect(later.pendingReferences, isEmpty);
    });

    test('what was observed before the restore wins over the record', () async {
      await observed(['a'], cells: {'a': _tofu});
      final version = Completer<String>();
      final later = probe(['a'], producer: () => version.future)
        ..observe('a', _art(1));

      version.complete('art-1');
      await later.completed;

      expect(later.supports(_key('a')), isTrue);
    });

    test('damaged or foreign records read as nothing', () async {
      for (final stored in [
        const StoredValue('{"artVersion": 3}', version: 1),
        const StoredValue('not json', version: 1),
        const StoredValue('[]', version: 1),
        const StoredValue('{}', version: 2),
      ]) {
        store = FakeKeyValueStore();
        await store.write('emoji_data', 'glyph_probe', stored);

        final subject = probe(['a']);
        await subject.start();

        expect(subject.isComplete, isFalse, reason: stored.value);
        expect(subject.pendingReferences, [_reference]);
      }
    });

    test('a store that cannot be read costs only the record', () async {
      store.failure = Exception('disk');
      final errors = <Object>[];
      await runZonedGuarded(() async {
        final subject = probe(['a'])
          ..observe(_reference, _tofu)
          ..observe('a', _tofu);
        await subject.completed;

        expect(subject.supports(_key('a')), isFalse);
      }, (error, _) => errors.add(error));

      expect(errors, isNotEmpty);
    });
  });

  group('a snapshot', () {
    test('round-trips through json', () async {
      final subject = await observed(['a', 'b'], cells: {'b': _tofu});

      final restored = GlyphProbeSnapshot.fromJson(subject.snapshot().toJson());

      expect(restored.artVersion, 'art-1');
      expect(restored.cellHashes.keys, unorderedEquals(['a', 'b']));
      expect(restored.referenceHashes, hasLength(1));
    });

    test('with damaged json is a FormatException', () {
      expect(
        () => GlyphProbeSnapshot.fromJson({'artVersion': 3}),
        throwsFormatException,
      );
    });
  });
}
