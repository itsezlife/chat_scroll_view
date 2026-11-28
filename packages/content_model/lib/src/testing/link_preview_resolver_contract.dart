import 'dart:async';

import 'package:content_model/content_model.dart';
import 'package:test/test.dart';

/// A [LinkPreviewResolver] under test, with the candidates the contract
/// needs and cannot invent.
final class LinkPreviewResolverHarness {
  /// Creates a harness around [resolver].
  const LinkPreviewResolverHarness({
    required this.resolver,
    required this.withPage,
    required this.withoutPage,
    required this.settle,
  });

  /// The resolver under test.
  final LinkPreviewResolver resolver;

  /// Candidates the resolver finds a page for.
  final List<Uri> withPage;

  /// Candidates none of which has a page.
  final List<Uri> withoutPage;

  /// Lets every request in flight reach its end, as far as the resolver
  /// takes it: a fake completes them, a real resolver waits for its backend.
  final Future<void> Function() settle;
}

/// The behaviour every [LinkPreviewResolver] must have, as a test suite to
/// run against an implementation.
abstract final class LinkPreviewResolverContract {
  /// How long a request may stay pending after [LinkPreviewResolverHarness]
  /// `settle` before the suite fails it.
  static const Duration _patience = Duration(seconds: 10);

  /// Runs the [LinkPreviewResolver] contract against the harnesses [create]
  /// returns, one per test.
  static void run(Future<LinkPreviewResolverHarness> Function() create) {
    group('LinkPreviewResolver contract', () {
      late LinkPreviewResolverHarness harness;
      late LinkPreviewResolver resolver;

      setUp(() async {
        harness = await create();
        resolver = harness.resolver;
      });

      // Settles the harness, then waits for the request's one move when
      // the resolver answers later than settle returns.
      Future<LinkPreviewState> ended(LinkPreviewRequest request) async {
        await harness.settle();
        if (request.value.isTerminal) return request.value;
        final moved = Completer<void>();
        void onChange() {
          if (!moved.isCompleted) moved.complete();
        }

        request.addListener(onChange);
        try {
          if (!request.value.isTerminal) {
            await moved.future.timeout(_patience);
          }
        } finally {
          request.removeListener(onChange);
        }
        return request.value;
      }

      test('a request starts pending', () {
        final request = resolver.resolve(harness.withPage);
        addTearDown(request.cancel);

        expect(request.value, LinkPreviewState.pending);
      });

      test('a page resolves to loaded', () async {
        final request = resolver.resolve(harness.withPage);

        expect(await ended(request), isA<LinkPreviewState$Loaded>());
      });

      test('candidates without a page resolve to none', () async {
        final request = resolver.resolve(harness.withoutPage);

        expect(await ended(request), LinkPreviewState.none);
      });

      test('an empty list resolves to none', () async {
        final request = resolver.resolve(const []);

        expect(await ended(request), LinkPreviewState.none);
      });

      test('moves once, with one notification at the terminal state', () async {
        final request = resolver.resolve(harness.withPage);
        final seen = <LinkPreviewState>[];
        request.addListener(() => seen.add(request.value));

        final state = await ended(request);
        await harness.settle();
        await pumpEventQueue();

        expect(seen, [state]);
        expect(request.value, state);
      });

      test('notifies no more after the terminal state', () async {
        final request = resolver.resolve(harness.withoutPage);
        await ended(request);
        var notified = 0;
        request.addListener(() => notified++);

        await harness.settle();
        await pumpEventQueue();

        expect(notified, 0);
        expect(request.value, LinkPreviewState.none);
      });

      test('notifies no more after cancel', () async {
        final request = resolver.resolve(harness.withPage);
        var notified = 0;
        request
          ..addListener(() => notified++)
          ..cancel();

        await harness.settle();
        await pumpEventQueue();

        expect(notified, 0);
        expect(request.value, LinkPreviewState.pending);
      });

      test('cancel twice is safe', () async {
        final request = resolver.resolve(harness.withPage)
          ..cancel()
          ..cancel();

        await harness.settle();

        expect(request.value, LinkPreviewState.pending);
      });

      test('cancel after the terminal state changes nothing', () async {
        final request = resolver.resolve(harness.withPage);
        final state = await ended(request);
        var notified = 0;
        request
          ..addListener(() => notified++)
          ..cancel();

        expect(request.value, state);
        expect(notified, 0);
      });

      test('a cancelled lookup does not hold back the next one', () async {
        resolver.resolve(harness.withPage).cancel();
        final again = resolver.resolve(harness.withPage);

        expect(await ended(again), isA<LinkPreviewState$Loaded>());
      });

      test('the same candidates can be resolved again', () async {
        final first = await ended(resolver.resolve(harness.withPage));
        final second = await ended(resolver.resolve(harness.withPage));

        expect(second, first);
      });
    });
  }
}
