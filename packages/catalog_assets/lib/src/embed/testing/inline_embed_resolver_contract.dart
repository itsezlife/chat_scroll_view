import 'package:catalog_assets/src/embed/inline_embed.dart';
import 'package:flutter_test/flutter_test.dart';

/// What an [InlineEmbedResolver] contract run needs besides the resolver.
final class InlineEmbedResolverHarness {
  /// Creates a harness around [resolver].
  const InlineEmbedResolverHarness({
    required this.resolver,
    required this.known,
    required this.unknown,
  });

  /// The resolver under test.
  final InlineEmbedResolver resolver;

  /// A target the resolver resolves.
  final InlineEmbedTarget known;

  /// A target it does not.
  final InlineEmbedTarget unknown;
}

/// The contract every [InlineEmbedResolver] meets; see its documentation.
abstract final class InlineEmbedResolverContract {
  /// Runs it as a test group. [create] builds a fresh harness for each test.
  static void run(InlineEmbedResolverHarness Function() create) {
    group('InlineEmbedResolver contract', () {
      late InlineEmbedResolverHarness harness;
      const metrics = InlineEmbedMetrics(
        fontSize: 15,
        ascent: 14,
        descent: 4,
        devicePixelRatio: 2,
      );

      setUp(() => harness = create());

      test('returns null for a target it does not know', () {
        expect(harness.resolver.resolve(harness.unknown, metrics), isNull);
      });

      test('resolves a known target to an embed with a size', () {
        final embed = harness.resolver.resolve(harness.known, metrics)!;
        addTearDown(embed.dispose);

        expect(embed.sizeHint.isEmpty, isFalse);
      });

      test('gives each call an embed of its own', () {
        final first = harness.resolver.resolve(harness.known, metrics)!;
        final second = harness.resolver.resolve(harness.known, metrics)!;
        addTearDown(second.dispose);

        expect(first, isNot(same(second)));
        first.dispose();
        expect(second.visible, isTrue);
      });
    });
  }
}
