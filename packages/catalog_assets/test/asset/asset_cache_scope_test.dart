import 'dart:ui';

import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/src/playback/playback_clock.dart';
import 'package:catalog_assets/testing.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter_test/flutter_test.dart';

const _sticker = ContentKey.document('sticker-1');
const _other = ContentKey.document('sticker-2');
const _spec = AssetSpec(pixelWidth: 64, pixelHeight: 64);
const _bigger = AssetSpec(pixelWidth: 128, pixelHeight: 128);
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

  group('staged readiness', () {
    test('a new attach is at stage none and paints the placeholder', () {
      final binding = scope.attach(_sticker, _spec, _profile);

      expect(binding.readiness, const AssetReadiness(AssetStage.none));
      expect(binding.paintable, same(scope.placeholder));
      expect(binding.key, _sticker);
      expect(binding.spec, _spec);
      expect(binding.profile, _profile);
    });

    test('without a producer an attach stays at none and never fails', () {
      final bare = AssetCacheScope(
        clock: PlaybackClock(ticks: ManualPlaybackTickSource()),
      );
      addTearDown(bare.dispose);

      final binding = bare.attach(_sticker, _spec, _profile);

      expect(binding.readiness.stage, AssetStage.none);
      expect(binding.lastError, isNull);
    });

    test('moves through placeholder, first frame and full, each signalled', () {
      final binding = scope.attach(_sticker, _spec, _profile);
      var signals = 0;
      binding.addListener(() => signals++);
      final attempt = producer.last;

      final placeholder = attempt.advance(AssetStage.placeholder);
      expect(binding.readiness, const AssetReadiness(AssetStage.placeholder));
      expect(binding.paintable, same(placeholder));

      final first = attempt.advance(AssetStage.firstFrame);
      expect(binding.readiness, const AssetReadiness(AssetStage.firstFrame));
      expect(binding.paintable, same(first));

      final full = attempt.advance(AssetStage.full);
      expect(
        binding.readiness,
        const AssetReadiness(AssetStage.full, isFinal: true),
      );
      expect(binding.paintable, same(full));
      expect(signals, 3);
    });

    test('a stage the next one replaces is disposed', () {
      scope.attach(_sticker, _spec, _profile);
      final attempt = producer.last;

      final placeholder = attempt.advance(AssetStage.placeholder);
      final first = attempt.advance(AssetStage.firstFrame);
      attempt.advance(AssetStage.full);

      expect(placeholder.disposals, 1);
      expect(first.disposals, 1);
    });

    test(
      'a stage below the current one is dropped and its paintable disposed',
      () {
        final binding = scope.attach(_sticker, _spec, _profile);
        final attempt = producer.last;
        final full = attempt.advance(AssetStage.firstFrame);
        var signals = 0;
        binding.addListener(() => signals++);

        final late = attempt.advance(AssetStage.placeholder);

        expect(binding.paintable, same(full));
        expect(late.disposals, 1);
        expect(full.disposals, 0);
        expect(signals, 0);
      },
    );

    test('only the first frame is final for a first-frame-only spec', () {
      const firstOnly = AssetSpec(
        pixelWidth: 64,
        pixelHeight: 64,
        variant: AssetVariant.firstFrame,
      );
      final binding = scope.attach(_sticker, firstOnly, _profile);

      producer.last.advance(AssetStage.firstFrame);

      expect(
        binding.readiness,
        const AssetReadiness(AssetStage.firstFrame, isFinal: true),
      );
    });

    test('a profile without autoplay keeps the placeholder until full', () {
      final binding = scope.attach(
        _sticker,
        _spec,
        const AssetProfile(autoplayFirstFrame: false),
      );
      final attempt = producer.last;

      attempt.advance(AssetStage.firstFrame);
      expect(binding.readiness.stage, AssetStage.placeholder);
      expect(binding.paintable, same(scope.placeholder));

      final full = attempt.advance(AssetStage.full);
      expect(binding.readiness.stage, AssetStage.full);
      expect(binding.paintable, same(full));
    });

    test('an answer given during produce is there when attach returns', () {
      producer.onProduce = (attempt) => attempt.advance(AssetStage.full);

      final binding = scope.attach(_sticker, _spec, _profile);

      expect(binding.readiness.isFinal, isTrue);
      expect(binding.paintable, isNot(same(scope.placeholder)));
    });
  });

  group('one entry per content and spec', () {
    test('two bindings on one entry share one attempt and one paintable', () {
      final a = scope.attach(_sticker, _spec, _profile);
      final b = scope.attach(_sticker, _spec, const AssetProfile(loop: false));

      final full = producer.last.advance(AssetStage.full);

      expect(producer.attempts, hasLength(1));
      expect(a.paintable, same(full));
      expect(b.paintable, same(full));
    });

    test('another size or another content is another entry', () {
      scope
        ..attach(_sticker, _spec, _profile)
        ..attach(_sticker, _bigger, _profile)
        ..attach(_other, _spec, _profile);

      expect(producer.attempts, hasLength(3));
    });

    test('an entry that is final is not produced again', () {
      final first = scope.attach(_sticker, _spec, _profile);
      producer.last.advance(AssetStage.full);
      first.detach();

      final again = scope.attach(_sticker, _spec, _profile);

      expect(producer.attempts, hasLength(1));
      expect(again.readiness.isFinal, isTrue);
    });
  });

  group('attach and detach', () {
    test('the entry is attached from attach until the last detach', () {
      final a = scope.attach(_sticker, _spec, _profile);
      final b = scope.attach(_sticker, _spec, _profile);
      expect(scope.isAttached(_sticker, _spec), isTrue);

      a.detach();
      expect(scope.isAttached(_sticker, _spec), isTrue);

      b.detach();
      expect(scope.isAttached(_sticker, _spec), isFalse);
    });

    test('detaching twice releases once', () {
      final a = scope.attach(_sticker, _spec, _profile);
      scope.attach(_sticker, _spec, _profile);

      a
        ..detach()
        ..detach();

      expect(scope.isAttached(_sticker, _spec), isTrue);
    });

    test('the last detach cancels an attempt still running', () {
      final a = scope.attach(_sticker, _spec, _profile);
      final b = scope.attach(_sticker, _spec, _profile);
      final attempt = producer.last;

      a.detach();
      expect(attempt.isCancelled, isFalse);

      b.detach();
      expect(attempt.isCancelled, isTrue);
    });

    test('a finished attempt is not cancelled by the last detach', () {
      final binding = scope.attach(_sticker, _spec, _profile);
      producer.last.advance(AssetStage.full);

      binding.detach();

      expect(producer.last.isCancelled, isFalse);
    });

    test(
      'an entry with nothing worth keeping is dropped on the last detach',
      () {
        final binding = scope.attach(_sticker, _spec, _profile);
        final placeholder = producer.last.advance(AssetStage.placeholder);

        binding.detach();

        expect(scope.contains(_sticker, _spec), isFalse);
        expect(placeholder.disposals, 1);
        expect(scope.bytesIn(AssetTier.still), 0);
      },
    );

    test('a first frame is kept for the next attach and the load resumes', () {
      final binding = scope.attach(_sticker, _spec, _profile);
      final first = producer.last.advance(AssetStage.firstFrame);
      binding.detach();
      expect(scope.contains(_sticker, _spec), isTrue);

      final again = scope.attach(_sticker, _spec, _profile);

      expect(again.paintable, same(first));
      expect(producer.attempts, hasLength(2), reason: 'not final: resume');
    });

    test('a detached binding is silent and paints the placeholder', () {
      final binding = scope.attach(_sticker, _spec, _profile);
      var signals = 0;
      binding.addListener(() => signals++);
      binding.detach();

      producer.last.advance(AssetStage.full);

      expect(signals, 0);
      expect(binding.paintable, same(scope.placeholder));
    });

    test('a removed listener hears nothing', () {
      final binding = scope.attach(_sticker, _spec, _profile);
      var signals = 0;
      void listener() => signals++;
      binding
        ..addListener(listener)
        ..removeListener(listener);

      producer.last.advance(AssetStage.full);

      expect(signals, 0);
    });

    test('attaching after dispose is a bug and says so', () {
      scope.dispose();

      expect(() => scope.attach(_sticker, _spec, _profile), throwsStateError);
    });
  });

  group('painting through a binding', () {
    test('paints the current paintable at the clock time', () {
      final binding = scope.attach(_sticker, _spec, _profile);
      final full = producer.last.advance(AssetStage.full);
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);

      binding.paint(
        canvas,
        const Rect.fromLTWH(0, 0, 10, 10),
        tint: const Color(0xFF112233),
        opacity: 0.5,
      );
      recorder.endRecording().dispose();

      expect(full.paints, hasLength(1));
      expect(full.paints.single.rect, const Rect.fromLTWH(0, 0, 10, 10));
      expect(full.paints.single.context.tint, const Color(0xFF112233));
      expect(full.paints.single.context.opacity, 0.5);
      expect(full.paints.single.context.time, scope.clock.now);
    });

    test('paints a rounded clip when the profile has a corner radius', () {
      final binding = scope.attach(
        _sticker,
        _spec,
        const AssetProfile(cornerRadius: 8),
      );
      final full = producer.last.advance(AssetStage.full);
      final recorder = PictureRecorder();

      binding.paint(Canvas(recorder), const Rect.fromLTWH(0, 0, 10, 10));
      recorder.endRecording().dispose();

      expect(full.paints, hasLength(1));
    });
  });

  group('the scope', () {
    test(
      'disposing cancels attempts, disposes paintables and silences bindings',
      () {
        final binding = scope.attach(_sticker, _spec, _profile);
        final attempt = producer.last;
        final first = attempt.advance(AssetStage.firstFrame);
        var signals = 0;
        binding.addListener(() => signals++);

        scope.dispose();
        attempt.advance(AssetStage.full);

        expect(attempt.isCancelled, isTrue);
        expect(first.disposals, 1);
        expect(signals, 0);
        expect(binding.detach, returnsNormally);
      },
    );

    test('disposing twice is harmless', () {
      scope
        ..dispose()
        ..dispose();
    });

    test('does not dispose a clock it was handed', () {
      final source = ManualPlaybackTickSource();
      final clock = PlaybackClock(ticks: source);
      AssetCacheScope(clock: clock).dispose();

      clock.register(_NoopTarget());

      expect(source.isRunning, isTrue);
      clock.dispose();
    });
  });
}

final class _NoopTarget implements PlaybackTarget {
  @override
  Duration get frameInterval => const Duration(milliseconds: 16);

  @override
  void tick(Duration now) {}
}
