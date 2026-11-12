import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/testing.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter_test/flutter_test.dart';

const _key = ContentKey.document('gif-1');
const _spec = AssetSpec(pixelWidth: 64, pixelHeight: 64);
const _profile = AssetProfile();

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

  group('a binding reads the download of its entry', () {
    test('nothing is downloading until the producer says so', () {
      final binding = scope.attach(_key, _spec, _profile);

      expect(binding.downloadProgress, isNull);
    });

    test('a reported fraction reaches every binding and signals them', () {
      final first = scope.attach(_key, _spec, _profile);
      final second = scope.attach(_key, _spec, _profile);
      var signals = 0;
      first.addListener(() => signals++);

      producer.last.download(0.25);

      expect(first.downloadProgress, 0.25);
      expect(second.downloadProgress, 0.25);
      expect(signals, 1);
    });

    test('a repeated fraction does not signal again', () {
      final binding = scope.attach(_key, _spec, _profile);
      producer.last.download(0.5);
      var signals = 0;
      binding.addListener(() => signals++);

      producer.last.download(0.5);

      expect(signals, 0);
    });

    test('a fraction outside 0..1 is clamped', () {
      final binding = scope.attach(_key, _spec, _profile);

      producer.last.download(1.5);

      expect(binding.downloadProgress, 1);
    });

    test('a memory hit inside the attach never downloads', () {
      producer.onProduce = (attempt) => attempt.advance(AssetStage.full);

      final binding = scope.attach(_key, _spec, _profile);

      expect(binding.downloadProgress, isNull);
    });

    test('a stage short of final keeps the download', () {
      final binding = scope.attach(_key, _spec, _profile);
      producer.last
        ..download(1)
        ..advance(AssetStage.placeholder);

      expect(binding.downloadProgress, 1);
    });
  });

  group('the download lasts while the content is missing', () {
    test('until the final stage', () {
      final binding = scope.attach(_key, _spec, _profile);
      producer.last
        ..download(1)
        ..advance(AssetStage.full);

      expect(binding.downloadProgress, isNull);
    });

    test('past a failure, which keeps the fraction', () {
      final binding = scope.attach(_key, _spec, _profile);
      producer.last.download(0.4);
      var signals = 0;
      binding.addListener(() => signals++);

      producer.last.fail(StateError('offline'));

      expect(binding.downloadProgress, 0.4);
      expect(signals, 0);
    });

    test('past a cancel by the producer', () {
      final binding = scope.attach(_key, _spec, _profile);
      producer.last
        ..download(0.4)
        ..cancelled();

      expect(binding.downloadProgress, 0.4);
    });

    test('a report after the attempt ended is ignored', () {
      final binding = scope.attach(_key, _spec, _profile);
      final attempt = producer.last..fail(StateError('offline'));

      attempt.download(0.9);

      expect(binding.downloadProgress, isNull);
    });

    test('a new attempt starts without the last one, and signals that', () {
      final binding = scope.attach(_key, _spec, _profile);
      producer.last
        ..download(0.4)
        ..fail(StateError('offline'));
      var signals = 0;
      binding.addListener(() => signals++);

      binding.retry();

      expect(binding.downloadProgress, isNull);
      expect(signals, 1);
    });

    test('a detached binding reads none', () {
      final binding = scope.attach(_key, _spec, _profile);
      producer.last.download(0.4);

      binding.detach();

      expect(binding.downloadProgress, isNull);
    });

    test('the last binding leaving forgets it', () {
      final binding = scope.attach(_key, _spec, _profile);
      producer.last
        ..download(0.4)
        ..advance(AssetStage.placeholder)
        ..fail(StateError('offline'));
      binding.detach();

      final again = scope.attach(_key, _spec, _profile);

      expect(again.downloadProgress, isNull);
    });
  });

  test('a glyph binding never downloads', () {
    final binding = scope.attach(
      const ContentKey.unicode('😀'),
      _spec,
      _profile,
    );

    expect(binding.downloadProgress, isNull);
  });
}
