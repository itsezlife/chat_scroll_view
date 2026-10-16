import 'package:catalog_assets/catalog_assets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'pipeline_harness.dart';

void main() {
  group('offline', () {
    late PipelineHarness harness;
    final item = sticker(1, thumbnail: true);

    /// A binding that reached its thumbnail, with the content fetch lost.
    Future<AssetBinding> placeholderThenLostContent(
      FetchFailure failure,
    ) async {
      final binding = harness.attach(item);
      harness.fetcher.fetchesOf(item.key, FetchPart.thumbnail).last.complete();
      await harness.settle();
      harness.fetcher.fetchesOf(item.key, FetchPart.content).last.fail(failure);
      await harness.settle();
      return binding;
    }

    void answerLatest(FetchPart part) {
      harness.fetcher.fetchesOf(item.key, part).last.complete();
    }

    setUp(() {
      harness = PipelineHarness(known: [item], autoFetch: false);
      addTearDown(harness.dispose);
    });

    test('a leaf keeps its current stage and shows no failure', () async {
      final binding = await placeholderThenLostContent(
        const FetchFailure.transient('offline'),
      );
      var signals = 0;
      binding.addListener(() => signals++);
      final shown = binding.paintable;

      harness.scope.connectivityRestored();
      harness.fetcher
          .fetchesOf(item.key, FetchPart.content)
          .last
          .fail(const FetchFailure.transient('still offline'));
      await harness.settle();

      expect(binding.readiness.stage, AssetStage.placeholder);
      expect(binding.paintable, same(shown));
      expect(binding.lastError, isA<FetchFailure>());
      expect(signals, 0, reason: 'a failure is not an event for the painter');
    });

    test('retries when connectivity returns', () async {
      final binding = await placeholderThenLostContent(
        const FetchFailure.transient('offline'),
      );
      final before = harness.fetcher.fetches.length;

      harness.scope.connectivityRestored();
      answerLatest(FetchPart.content);
      await harness.settle();

      expect(harness.fetcher.fetches.length, greaterThan(before));
      expect(binding.readiness.stage, AssetStage.full);
      expect(binding.lastError, isNull);
    });

    test(
      'a permanent failure waits for something other than the network',
      () async {
        final binding = await placeholderThenLostContent(
          const FetchFailure.permanent('gone'),
        );
        final before = harness.fetcher.fetches.length;

        harness.scope.connectivityRestored();
        await harness.settle();

        expect(harness.fetcher.fetches, hasLength(before));
        expect(binding.readiness.stage, AssetStage.placeholder);
      },
    );

    test('retries on an explicit retry, after either class', () async {
      for (final failure in const [
        FetchFailure.transient('offline'),
        FetchFailure.permanent('gone'),
      ]) {
        harness = PipelineHarness(known: [item], autoFetch: false);
        addTearDown(harness.dispose);
        final binding = await placeholderThenLostContent(failure);
        final before = harness.fetcher.fetches.length;

        binding.retry();

        expect(
          harness.fetcher.fetches.length,
          greaterThan(before),
          reason: '${failure.kind}',
        );
      }
    });

    test('retries on re-attach, after either class', () async {
      for (final failure in const [
        FetchFailure.transient('offline'),
        FetchFailure.permanent('gone'),
      ]) {
        harness = PipelineHarness(known: [item], autoFetch: false);
        addTearDown(harness.dispose);
        final binding = await placeholderThenLostContent(failure);
        final before = harness.fetcher.fetches.length;

        binding.detach();
        final again = harness.attach(item);
        answerLatest(FetchPart.content);
        await harness.settle();

        expect(
          harness.fetcher.fetches.length,
          greaterThan(before),
          reason: '${failure.kind}',
        );
        expect(again.readiness.stage, AssetStage.full);
      }
    });

    test('an error that is not a FetchFailure counts as transient', () async {
      final binding = harness.attach(item);
      harness.fetcher
          .fetchesOf(item.key, FetchPart.content)
          .single
          .failWith(StateError('socket closed'));
      await harness.settle();
      final before = harness.fetcher.fetches.length;

      harness.scope.connectivityRestored();

      expect(harness.fetcher.fetches.length, greaterThan(before));
      expect(binding.lastError, isStateError);
    });

    test('goes back to full speed once the network is back', () async {
      final fast = PipelineHarness(known: [item]);
      addTearDown(fast.dispose);
      fast.fetcher.online = false;
      final binding = fast.attach(item);
      await fast.settle();
      expect(binding.readiness.stage, AssetStage.none);

      fast.fetcher.online = true;
      fast.scope.connectivityRestored();
      await fast.settle();

      expect(binding.readiness.stage, AssetStage.full);
    });
  });
}
