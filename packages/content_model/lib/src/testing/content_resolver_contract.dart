import 'package:content_model/content_model.dart';
import 'package:test/test.dart';

/// A [ContentResolver] under test, with the content the contract needs and
/// cannot invent.
final class ContentResolverHarness {
  /// Creates a harness around [resolver].
  const ContentResolverHarness({
    required this.resolver,
    required this.known,
    required this.unknownKey,
  });

  /// The resolver under test.
  final ContentResolver resolver;

  /// At least two descriptors the resolver resolves.
  final List<ContentDescriptor> known;

  /// A key the resolver cannot resolve.
  final ContentKey unknownKey;
}

/// The behaviour every [ContentResolver] must have, as a test suite to run
/// against an implementation.
abstract final class ContentResolverContract {
  /// Runs the [ContentResolver] contract against the harnesses [create]
  /// returns, one per test.
  static void run(Future<ContentResolverHarness> Function() create) {
    group('ContentResolver contract', () {
      late ContentResolverHarness harness;
      late ContentResolver resolver;

      setUp(() async {
        harness = await create();
        resolver = harness.resolver;
      });

      test('resolves nothing to an empty result', () async {
        expect(await resolver.resolve(const []), isEmpty);
      });

      test('resolves a key to its descriptor', () async {
        final descriptor = harness.known.first;

        final result = await resolver.resolve([descriptor.key]);

        expect(result, {descriptor.key: descriptor});
      });

      test('resolves a batch in one call', () async {
        final keys = [for (final d in harness.known) d.key];

        final result = await resolver.resolve(keys);

        expect(result.keys.toSet(), keys.toSet());
        for (final descriptor in harness.known) {
          expect(result[descriptor.key], descriptor);
        }
      });

      test('lists every descriptor under its own key', () async {
        final result = await resolver.resolve([
          for (final d in harness.known) d.key,
        ]);

        for (final MapEntry(:key, :value) in result.entries) {
          expect(value.key, key);
        }
      });

      test('leaves an unknown key out rather than failing', () async {
        final known = harness.known.first;

        final result = await resolver.resolve([harness.unknownKey, known.key]);

        expect(result.containsKey(harness.unknownKey), isFalse);
        expect(result[known.key], known);
      });

      test('resolves only unknown keys to an empty result', () async {
        expect(await resolver.resolve([harness.unknownKey]), isEmpty);
      });

      test('never holds a key that was not asked for', () async {
        final asked = harness.known.first.key;

        final result = await resolver.resolve([asked]);

        expect(result.keys, [asked]);
      });

      test('accepts a key more than once', () async {
        final descriptor = harness.known.first;

        final result = await resolver.resolve([
          descriptor.key,
          descriptor.key,
          harness.unknownKey,
          harness.unknownKey,
        ]);

        expect(result, {descriptor.key: descriptor});
      });

      test('can be asked again for the same keys', () async {
        final keys = [for (final d in harness.known) d.key];

        final first = await resolver.resolve(keys);
        final second = await resolver.resolve(keys);

        expect(second, first);
      });
    });
  }
}
