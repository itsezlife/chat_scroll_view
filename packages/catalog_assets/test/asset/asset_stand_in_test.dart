import 'dart:ui';

import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/src/playback/playback_clock.dart';
import 'package:catalog_assets/testing.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter_test/flutter_test.dart';

const _key = ContentKey.document('gif-1');
const _spec = AssetSpec(pixelWidth: 64, pixelHeight: 64);
const _profile = AssetProfile();
const _rect = Rect.fromLTWH(0, 0, 40, 40);

void main() {
  late FakeAssetProducer producer;
  late AssetCacheScope scope;
  late Canvas canvas;

  setUp(() {
    producer = FakeAssetProducer();
    scope = AssetCacheScope(
      producer: producer,
      clock: PlaybackClock(ticks: ManualPlaybackTickSource()),
    );
    canvas = Canvas(PictureRecorder());
  });
  tearDown(() => scope.dispose());

  group('stand-in kept under arriving content', () {
    test(
      'the thumbnail outlives the stage that replaces it until released',
      () {
        final binding = scope.attach(_key, _spec, _profile);
        final thumbnail = producer.last.advance(AssetStage.placeholder);
        expect(binding.paintStandIn(canvas, _rect), isFalse);

        producer.last.advance(AssetStage.firstFrame);

        expect(thumbnail.isDisposed, isFalse);
        expect(binding.paintStandIn(canvas, _rect), isTrue);
        expect(thumbnail.paints, hasLength(1));
        expect(thumbnail.paints.single.rect, _rect);

        binding.releaseStandIn();

        expect(thumbnail.isDisposed, isTrue);
        expect(binding.paintStandIn(canvas, _rect), isFalse);
      },
    );

    test('content that arrives with no thumbnail has no stand-in', () {
      final binding = scope.attach(_key, _spec, _profile);

      producer.last.advance(AssetStage.firstFrame);

      expect(binding.paintStandIn(canvas, _rect), isFalse);
    });

    test('a later stage keeps it: the fade can outlast the first frame', () {
      final binding = scope.attach(_key, _spec, _profile);
      final thumbnail = producer.last.advance(AssetStage.placeholder);
      producer.last.advance(AssetStage.firstFrame);
      producer.last.advance(AssetStage.full);

      expect(thumbnail.isDisposed, isFalse);
      expect(binding.paintStandIn(canvas, _rect), isTrue);
    });

    test('a binding attached after the content arrived has none', () {
      final first = scope.attach(_key, _spec, _profile);
      final thumbnail = producer.last.advance(AssetStage.placeholder);
      producer.last.advance(AssetStage.firstFrame);

      final late = scope.attach(_key, _spec, _profile);

      expect(late.paintStandIn(canvas, _rect), isFalse);
      expect(first.paintStandIn(canvas, _rect), isTrue);
      expect(thumbnail.isDisposed, isFalse);
    });

    test('it is freed only when every binding that waited released it', () {
      final one = scope.attach(_key, _spec, _profile);
      final two = scope.attach(_key, _spec, _profile);
      final thumbnail = producer.last.advance(AssetStage.placeholder);
      producer.last.advance(AssetStage.firstFrame);

      one.releaseStandIn();
      expect(thumbnail.isDisposed, isFalse);
      expect(two.paintStandIn(canvas, _rect), isTrue);

      two.releaseStandIn();
      expect(thumbnail.isDisposed, isTrue);
    });

    test('painting the content opaque releases it, translucent does not', () {
      final binding = scope.attach(_key, _spec, _profile);
      final thumbnail = producer.last.advance(AssetStage.placeholder);
      producer.last.advance(AssetStage.firstFrame);

      binding.paint(canvas, _rect, opacity: 0.5);
      expect(thumbnail.isDisposed, isFalse);

      binding.paint(canvas, _rect);
      expect(thumbnail.isDisposed, isTrue);
    });

    test('painting the thumbnail itself does not release it', () {
      final binding = scope.attach(_key, _spec, _profile);
      final thumbnail = producer.last.advance(AssetStage.placeholder);

      binding.paint(canvas, _rect);

      expect(thumbnail.isDisposed, isFalse);
      expect(thumbnail.paints, hasLength(1));
    });

    test('releasing twice changes nothing', () {
      final one = scope.attach(_key, _spec, _profile);
      final two = scope.attach(_key, _spec, _profile);
      final thumbnail = producer.last.advance(AssetStage.placeholder);
      producer.last.advance(AssetStage.firstFrame);

      one
        ..releaseStandIn()
        ..releaseStandIn();

      expect(thumbnail.isDisposed, isFalse);
      expect(two.paintStandIn(canvas, _rect), isTrue);
    });

    test('detaching gives the hold back like a release', () {
      final binding = scope.attach(_key, _spec, _profile);
      final thumbnail = producer.last.advance(AssetStage.placeholder);
      producer.last.advance(AssetStage.firstFrame);

      binding.detach();

      expect(thumbnail.isDisposed, isTrue);
    });
  });
}
