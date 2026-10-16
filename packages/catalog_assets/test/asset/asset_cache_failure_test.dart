import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/testing.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter_test/flutter_test.dart';

const _key = ContentKey.document('sticker-1');
const _spec = AssetSpec(pixelWidth: 64, pixelHeight: 64);
const _profile = AssetProfile();
const _offline = 'offline';

void main() {
  late FakeAssetProducer producer;
  late AssetCacheScope scope;

  setUp(() {
    producer = FakeAssetProducer();
    scope = AssetCacheScope(
      producer: producer,
      clock: PlaybackClock(ticks: ManualPlaybackTickSource()),
    );
  });
  tearDown(() => scope.dispose());

  group('no visible failure', () {
    test('a failed attempt leaves the stage and signals nothing', () {
      final binding = scope.attach(_key, _spec, _profile);
      final placeholder = producer.last.advance(AssetStage.placeholder);
      var signals = 0;
      binding.addListener(() => signals++);

      producer.last.fail(_offline);

      expect(binding.readiness.stage, AssetStage.placeholder);
      expect(binding.readiness.isFinal, isFalse);
      expect(binding.paintable, same(placeholder));
      expect(signals, 0);
    });

    test('keeps the error for diagnostics until an attempt advances', () {
      final binding = scope.attach(_key, _spec, _profile);

      producer.last.fail(_offline);
      expect(binding.lastError, _offline);

      binding.retry();
      producer.last.advance(AssetStage.firstFrame);
      expect(binding.lastError, isNull);
    });

    test('cancellation is not a failure', () {
      final binding = scope.attach(_key, _spec, _profile);

      producer.last.cancelled();

      expect(binding.lastError, isNull);
      expect(binding.readiness.stage, AssetStage.none);
    });

    test(
      'a result from an attempt that already ended is ignored and freed',
      () {
        final binding = scope.attach(_key, _spec, _profile);
        final attempt = producer.last;
        attempt.fail(_offline);

        final late = attempt.advance(AssetStage.full);

        expect(binding.readiness.stage, AssetStage.none);
        expect(late.disposals, 1);
      },
    );

    test('a result from a cancelled attempt cannot reach a newer one', () {
      final first = scope.attach(_key, _spec, _profile);
      final cancelled = producer.last;
      first.detach();
      final second = scope.attach(_key, _spec, _profile);
      final fresh = producer.last;

      final late = cancelled.advance(AssetStage.full);

      expect(second.readiness.stage, AssetStage.none);
      expect(late.disposals, 1);
      fresh.advance(AssetStage.placeholder);
      expect(second.readiness.stage, AssetStage.placeholder);
    });

    test('a producer that throws is a recorded failure, not a crash', () {
      final throwing = AssetCacheScope(
        producer: _ThrowingProducer(),
        clock: PlaybackClock(ticks: ManualPlaybackTickSource()),
      );
      addTearDown(throwing.dispose);

      final binding = throwing.attach(_key, _spec, _profile);

      expect(binding.lastError, isA<StateError>());
      expect(binding.readiness.stage, AssetStage.none);
    });
  });

  group('recovery', () {
    test('a failed entry is attempted again when a surface re-attaches', () {
      final first = scope.attach(_key, _spec, _profile);
      producer.last.advance(AssetStage.firstFrame);
      producer.last.fail(_offline, kind: AssetFailureKind.permanent);
      first.detach();

      scope.attach(_key, _spec, _profile);

      expect(producer.attempts, hasLength(2));
    });

    test(
      'retry attempts again now, once, and only when nothing is running',
      () {
        final binding = scope.attach(_key, _spec, _profile);
        binding.retry();
        expect(producer.attempts, hasLength(1), reason: 'still running');

        producer.last.fail(_offline);
        binding
          ..retry()
          ..retry();

        expect(producer.attempts, hasLength(2));
      },
    );

    test('retry does nothing for a final entry or a detached binding', () {
      final binding = scope.attach(_key, _spec, _profile);
      producer.last.advance(AssetStage.full);
      binding.retry();
      expect(producer.attempts, hasLength(1));

      final other = scope.attach(
        const ContentKey.document('x'),
        _spec,
        _profile,
      );
      producer.last.fail(_offline);
      other
        ..detach()
        ..retry();
      expect(producer.attempts, hasLength(2));
    });

    test('connectivity repeats a transient failure for attached entries', () {
      final binding = scope.attach(_key, _spec, _profile);
      producer.last.fail(_offline);

      scope.connectivityRestored();

      expect(producer.attempts, hasLength(2));
      producer.last.advance(AssetStage.full);
      expect(binding.readiness.isFinal, isTrue);
    });

    test('connectivity leaves a permanent failure alone', () {
      scope.attach(_key, _spec, _profile);
      producer.last.fail('corrupt', kind: AssetFailureKind.permanent);

      scope.connectivityRestored();

      expect(producer.attempts, hasLength(1));
    });

    test('connectivity does not restart an attempt that is running', () {
      scope.attach(_key, _spec, _profile);

      scope.connectivityRestored();

      expect(producer.attempts, hasLength(1));
    });

    test('connectivity ignores entries nobody is attached to', () {
      final binding = scope.attach(_key, _spec, _profile);
      producer.last.advance(AssetStage.firstFrame);
      producer.last.fail(_offline);
      binding.detach();

      scope.connectivityRestored();

      expect(producer.attempts, hasLength(1));
    });

    test('offline, then back: the cell shows its placeholder throughout', () {
      final binding = scope.attach(_key, _spec, _profile);
      final thumb = producer.last.advance(AssetStage.placeholder);
      var signals = 0;
      binding.addListener(() => signals++);

      producer.last.fail(_offline);
      expect(binding.paintable, same(thumb));
      expect(binding.readiness.stage, AssetStage.placeholder);

      scope.connectivityRestored();
      expect(binding.paintable, same(thumb), reason: 'no flash while retrying');

      final full = producer.last.advance(AssetStage.full);
      expect(binding.paintable, same(full));
      expect(signals, 1, reason: 'only the real change is signalled');
    });
  });
}

final class _ThrowingProducer implements AssetProducer {
  @override
  AssetTask produce(AssetRequest request, AssetProgress progress) =>
      throw StateError('producer bug');
}
