import 'package:catalog_assets/src/asset/asset_producer.dart';
import 'package:catalog_assets/src/pipeline/cancellation_token.dart';
import 'package:catalog_assets/src/pipeline/content_fetcher.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter_test/flutter_test.dart';

/// What a [ContentFetcher] contract run needs besides the fetcher.
final class AssetFetcherHarness {
  /// Creates a harness around [fetcher].
  const AssetFetcherHarness({
    required this.fetcher,
    required this.available,
    required this.missing,
    this.elapse = _noop,
    this.goOffline,
    this.goOnline,
  });

  /// The fetcher under test.
  final ContentFetcher fetcher;

  /// A descriptor the fetcher can serve content for. When it has a
  /// `thumbnail`, the fetcher can serve that as well.
  final ContentDescriptor available;

  /// A descriptor the host has nothing for, thumbnail included.
  final ContentDescriptor missing;

  /// Lets time pass for a fetcher that answers after a delay (a manual
  /// clock). A real adapter leaves the default.
  final void Function() elapse;

  /// Cuts the fetcher off from its source, or null if it cannot be.
  final void Function()? goOffline;

  /// Undoes [goOffline].
  final void Function()? goOnline;

  static void _noop() {}
}

/// The contract every [ContentFetcher] meets; see its documentation.
abstract final class AssetFetcherContract {
  /// Runs it as a test group. [create] builds a fresh harness for each test.
  static void run(AssetFetcherHarness Function() create) {
    group('ContentFetcher contract', () {
      late AssetFetcherHarness harness;
      late CancellationToken token;

      setUp(() {
        harness = create();
        token = CancellationToken();
      });

      FetchRequest request(
        ContentDescriptor descriptor, [
        FetchPart part = FetchPart.content,
      ]) => FetchRequest(
        descriptor: descriptor,
        part: part,
        priority: AssetPriority.visible,
        cancellation: token,
      );

      Future<Object?> outcome(Future<FetchedContent> fetch) =>
          fetch.then<Object?>(
            (content) => content,
            onError: (Object error) => error,
          );

      test('serves the content of available content', () async {
        final result = harness.fetcher.fetch(request(harness.available));
        harness.elapse();

        expect(await result, isA<FetchedContent>());
      });

      test('serves the thumbnail of content that has one', () async {
        if (harness.available.thumbnail == null) return;
        final result = harness.fetcher.fetch(
          request(harness.available, FetchPart.thumbnail),
        );
        harness.elapse();

        expect(await result, isA<FetchedContent>());
      });

      test('fails permanently for content the host does not have', () async {
        final result = outcome(harness.fetcher.fetch(request(harness.missing)));
        harness.elapse();

        final error = await result;

        expect(error, isA<FetchFailure>());
        expect((error! as FetchFailure).kind, AssetFailureKind.permanent);
      });

      test('reports failure through the future, never by throwing', () {
        expect(
          () => outcome(harness.fetcher.fetch(request(harness.missing))),
          returnsNormally,
        );
        harness.elapse();
      });

      test('fails transiently while offline, and recovers', () async {
        final goOffline = harness.goOffline;
        final goOnline = harness.goOnline;
        if (goOffline == null || goOnline == null) return;

        goOffline();
        final lost = outcome(harness.fetcher.fetch(request(harness.available)));
        harness.elapse();
        final error = await lost;
        expect(error, isA<FetchFailure>());
        expect((error! as FetchFailure).kind, AssetFailureKind.transient);

        goOnline();
        final back = harness.fetcher.fetch(request(harness.available));
        harness.elapse();
        expect(await back, isA<FetchedContent>());
      });

      test(
        'settles a fetch that is cancelled, never leaves it pending',
        () async {
          final result = outcome(
            harness.fetcher.fetch(request(harness.available)),
          );

          token.cancel();

          await result.timeout(
            const Duration(seconds: 5),
            onTimeout: () => fail('a cancelled fetch must settle'),
          );
        },
      );

      test('runs fetches side by side without mixing them up', () async {
        final first = harness.fetcher.fetch(request(harness.available));
        final second = harness.fetcher.fetch(
          FetchRequest(
            descriptor: harness.missing,
            part: FetchPart.content,
            priority: AssetPriority.preload,
            cancellation: CancellationToken(),
          ),
        );
        harness.elapse();

        expect(await first, isA<FetchedContent>());
        await expectLater(second, throwsA(isA<FetchFailure>()));
      });
    });
  }
}
