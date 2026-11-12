import 'package:content_model/content_model.dart';
import 'package:test/test.dart';

/// A [PackSource] under test, with the facts about its packs that the
/// contract needs and cannot invent.
final class PackSourceHarness {
  /// Creates a harness around [source].
  const PackSourceHarness({
    required this.source,
    required this.known,
    required this.missingId,
    this.failLookups,
    this.publish,
    this.fetches,
  });

  /// The source under test, fresh: nothing looked up yet.
  final PackSource source;

  /// A pack the source finds.
  final Pack known;

  /// An id the source answers as not found.
  final PackId missingId;

  /// Makes fetches fail (`failing: true`) or succeed again, for a source
  /// whose backend can be made to. When null, the failure tests are skipped.
  final void Function({required bool failing})? failLookups;

  /// Makes the backend serve [pack] for its id from the next fetch on, as a
  /// publisher editing a pack would. When null, the refresh tests are
  /// skipped.
  final void Function(Pack pack)? publish;

  /// How many fetches of [PackId] reached the backend. When null, the tests
  /// that count fetches are skipped.
  final int Function(PackId id)? fetches;
}

/// The behaviour every [PackSource] must have, as a test suite to run against
/// an implementation.
abstract final class PackSourceContract {
  /// Runs the [PackSource] contract against the harnesses [create] returns,
  /// one per test.
  static void run(Future<PackSourceHarness> Function() create) {
    group('PackSource contract', () {
      late PackSourceHarness harness;
      late PackSource source;
      late int signals;

      PackId knownId() => harness.known.id;

      setUp(() async {
        harness = await create();
        source = harness.source;
        signals = 0;
        source.changes.addListener(() => signals++);
      });

      tearDown(() => source.dispose());

      group('lookup', () {
        test('finds a known pack', () async {
          expect(
            await source.lookup(knownId()),
            PackLookup.found(harness.known),
          );
        });

        test('answers a missing pack as not found', () async {
          expect(await source.lookup(harness.missingId), PackLookup.notFound);
        });

        test('answers a failure as failed, never as an error', () async {
          final fail = harness.failLookups;
          if (fail == null) return markTestSkipped('no failure switch');
          fail(failing: true);

          expect(await source.lookup(knownId()), isA<PackLookup$Failed>());
        });

        test('tries a failed pack again on the next lookup', () async {
          final fail = harness.failLookups;
          if (fail == null) return markTestSkipped('no failure switch');
          fail(failing: true);
          await source.lookup(knownId());
          fail(failing: false);

          expect(
            await source.lookup(knownId()),
            PackLookup.found(harness.known),
          );
        });

        test('shares one fetch between lookups in flight', () async {
          final first = source.lookup(knownId());
          final second = source.lookup(knownId());

          expect(await second, PackLookup.found(harness.known));
          expect(await first, PackLookup.found(harness.known));
          if (harness.fetches case final fetches?) {
            expect(fetches(knownId()), 1);
          }
        });

        test('answers a found pack again without fetching', () async {
          final fetches = harness.fetches;
          if (fetches == null) return markTestSkipped('no fetch count');
          await source.lookup(knownId());

          expect(
            await source.lookup(knownId()),
            PackLookup.found(harness.known),
          );
          expect(fetches(knownId()), 1);
        });

        test('keeps a missing pack missing without fetching', () async {
          final fetches = harness.fetches;
          if (fetches == null) return markTestSkipped('no fetch count');
          await source.lookup(harness.missingId);

          expect(await source.lookup(harness.missingId), PackLookup.notFound);
          expect(fetches(harness.missingId), 1);
        });
      });

      group('peek', () {
        test('is idle before any lookup', () {
          expect(source.peek(knownId()), PackLookup.idle);
        });

        test('is loading while the first lookup is in flight', () async {
          final pending = source.lookup(knownId());

          expect(source.peek(knownId()), PackLookup.loading);
          await pending;
        });

        test('answers the last answer', () async {
          await source.lookup(knownId());
          await source.lookup(harness.missingId);

          expect(source.peek(knownId()), PackLookup.found(harness.known));
          expect(source.peek(harness.missingId), PackLookup.notFound);
        });

        test('answers a failure until the next lookup', () async {
          final fail = harness.failLookups;
          if (fail == null) return markTestSkipped('no failure switch');
          fail(failing: true);
          await source.lookup(knownId());

          expect(source.peek(knownId()), isA<PackLookup$Failed>());
        });
      });

      group('changes', () {
        test('signals the start and the answer of a lookup', () async {
          final seen = <PackLookup>[];
          source.changes.addListener(() => seen.add(source.peek(knownId())));

          await source.lookup(knownId());

          expect(seen, [PackLookup.loading, PackLookup.found(harness.known)]);
        });

        test('stays silent when an answer is served from memory', () async {
          await source.lookup(knownId());
          signals = 0;

          await source.lookup(knownId());

          expect(signals, 0);
        });
      });

      group('refresh', () {
        test('fetches a held pack again and answers the new one', () async {
          final publish = harness.publish;
          if (publish == null) return markTestSkipped('no publish switch');
          await source.lookup(knownId());
          final edited = Pack(
            id: knownId(),
            kind: harness.known.kind,
            title: '${harness.known.title} (edited)',
            items: harness.known.items,
          );
          publish(edited);

          expect(
            await source.lookup(knownId(), refresh: true),
            PackLookup.found(edited),
          );
          expect(source.peek(knownId()), PackLookup.found(edited));
        });

        test('keeps answering the held pack while it refreshes', () async {
          await source.lookup(knownId());

          final pending = source.lookup(knownId(), refresh: true);

          expect(source.peek(knownId()), PackLookup.found(harness.known));
          await pending;
        });

        test('keeps the held pack when the refresh fails', () async {
          final fail = harness.failLookups;
          if (fail == null) return markTestSkipped('no failure switch');
          await source.lookup(knownId());
          fail(failing: true);

          expect(
            await source.lookup(knownId(), refresh: true),
            PackLookup.found(harness.known),
          );
          expect(source.peek(knownId()), PackLookup.found(harness.known));
        });

        test('is silent when nothing changed', () async {
          await source.lookup(knownId());
          signals = 0;

          await source.lookup(knownId(), refresh: true);

          expect(signals, 0);
        });
      });

      group('after dispose', () {
        test('is silent and answers what it held', () async {
          await source.lookup(knownId());
          signals = 0;

          source.dispose();

          expect(
            await source.lookup(knownId()),
            PackLookup.found(harness.known),
          );
          expect(await source.lookup(harness.missingId), PackLookup.idle);
          expect(signals, 0);
        });

        test('drops a lookup in flight', () async {
          final pending = source.lookup(knownId());
          source.dispose();

          await pending;

          expect(source.peek(knownId()), PackLookup.loading);
          expect(signals, 1);
        });

        test('can be disposed twice', () {
          source.dispose();

          expect(source.dispose, returnsNormally);
        });
      });
    });
  }
}
