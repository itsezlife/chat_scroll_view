import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/testing.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeFrameTextureHost host;
  late ValueNotifier<bool> scrolling;
  late FrameTexturePool pool;

  setUp(() {
    host = FakeFrameTextureHost();
    scrolling = ValueNotifier<bool>(false);
    pool = FrameTexturePool(
      host: host,
      scrolling: scrolling,
      reuseDelay: Duration.zero,
    );
  });

  tearDown(() {
    pool.dispose();
    scrolling.dispose();
  });

  group('lease', () {
    test('finds nothing before a warm: the asset keeps its page slot', () {
      expect(pool.lease(100, 100), isNull);
      expect(host.created, isEmpty, reason: 'a lease never creates');
    });

    test(
      'takes a warmed texture of the size class, square at its edge',
      () async {
        await pool.warm(128, 2);

        final first = pool.lease(100, 90)!;
        final second = pool.lease(128, 40)!;

        expect(host.created, [
          (width: 128, height: 128),
          (width: 128, height: 128),
        ]);
        expect(first.texture.width, 128);
        expect(first.texture.height, 128);
        expect(
          host.liveIds,
          containsAll([first.texture.id, second.texture.id]),
        );
        expect(first.texture.id, isNot(second.texture.id));
      },
    );

    test('finds nothing when every texture of the class is leased', () async {
      await pool.warm(128, 1);
      pool.lease(100, 100);

      expect(pool.lease(100, 100), isNull);
      expect(host.created, hasLength(1), reason: 'a lease never creates');
    });

    test('never takes a texture of another class', () async {
      await pool.warm(256, 1);

      expect(pool.lease(100, 100), isNull);
      expect(pool.lease(200, 200), isNotNull);
    });

    test('a chat sticker at 3x leases the 384 class, not 512', () {
      expect(pool.classOf(336, 336), 384);
      expect(pool.classOf(300, 169), 384);
      expect(pool.classOf(385, 100), 512);
    });

    test('finds nothing above the largest class', () async {
      await pool.warm(512, 1);

      expect(pool.lease(600, 100), isNull);
    });
  });

  group('release', () {
    test('idles the texture for the next lease, without a new one', () async {
      await pool.warm(128, 1);
      final first = pool.lease(100, 100)!..release();

      final second = pool.lease(100, 100)!;

      expect(second.texture, first.texture);
      expect(host.created, hasLength(1));
      expect(host.destroyed, isEmpty);
    });

    test('keeps a released texture from a lease for the reuse delay: a '
        'surface may still show it', () async {
      var now = Duration.zero;
      final timed = FrameTexturePool(host: host, now: () => now);
      addTearDown(timed.dispose);
      await timed.warm(128, 1);
      timed.lease(100, 100)!.release();

      now =
          FrameTexturePool.defaultReuseDelay - const Duration(milliseconds: 1);
      expect(timed.lease(100, 100), isNull);
      expect(timed.idleTextures, 1);

      now = FrameTexturePool.defaultReuseDelay;
      expect(timed.lease(100, 100), isNotNull);
    });

    test('leases the texture released longest ago first', () async {
      var now = Duration.zero;
      final timed = FrameTexturePool(host: host, now: () => now);
      addTearDown(timed.dispose);
      await timed.warm(128, 2);
      final a = timed.lease(100, 100)!;
      final b = timed.lease(100, 100)!;
      a.release();
      now += const Duration(milliseconds: 10);
      b.release();
      now += FrameTexturePool.defaultReuseDelay;

      expect(timed.lease(100, 100)!.texture.id, a.texture.id);
    });

    test('a warmed texture is leased at once', () async {
      final timed = FrameTexturePool(host: host, now: () => Duration.zero);
      addTearDown(timed.dispose);
      await timed.warm(128, 1);

      expect(timed.lease(100, 100), isNotNull);
    });

    test('is idempotent', () async {
      await pool.warm(128, 1);
      final first = pool.lease(100, 100)!
        ..release()
        ..release();
      pool.lease(100, 100);

      expect(first.isReleased, isTrue);
      expect(pool.lease(100, 100), isNull, reason: 'one texture, one lease');
    });

    test('destroys a texture that would idle past the idle limit', () async {
      pool.dispose();
      pool = FrameTexturePool(host: host, scrolling: scrolling, idleLimit: 1);
      await pool.warm(128, 1);
      await pool.warm(256, 1);
      final small = pool.lease(100, 100)!;
      final large = pool.lease(200, 200)!;

      small.release();
      large.release();

      expect(host.destroyed, [small.texture.id], reason: 'the oldest goes');
      expect(pool.idleTextures, 1);
    });

    test('discard destroys the texture instead of idling it', () async {
      await pool.warm(128, 1);
      final lease = pool.lease(100, 100)!..discard();

      expect(host.destroyed, [lease.texture.id]);
      expect(lease.isReleased, isTrue);
      expect(pool.lease(100, 100), isNull);
    });
  });

  group('memory pressure', () {
    test(
      'releaseIdle destroys every idle texture and spares leased ones',
      () async {
        await pool.warm(128, 3);
        final held = pool.lease(100, 100)!;

        pool.releaseIdle();

        expect(host.destroyed, hasLength(2));
        expect(host.liveIds, [held.texture.id]);
        expect(pool.idleTextures, 0);
        held.release();
        expect(host.destroyed, hasLength(2), reason: 'it idles afterwards');
      },
    );
  });

  group('dispose', () {
    test(
      'destroys every texture, leased ones when they are released',
      () async {
        await pool.warm(128, 2);
        final held = pool.lease(100, 100)!;

        pool.dispose();
        expect(host.liveIds, [held.texture.id]);
        held.release();

        expect(host.liveIds, isEmpty);
        expect(pool.lease(100, 100), isNull);
      },
    );
  });

  group('warm', () {
    test('tops the class up to the count of idle textures', () async {
      await pool.warm(128, 2);
      await pool.warm(128, 2);
      final held = pool.lease(100, 100)!;
      await pool.warm(128, 2);

      expect(host.created, hasLength(3));
      held.release();
    });

    test('two warms at once create the count once', () async {
      await Future.wait([pool.warm(128, 2), pool.warm(128, 2)]);

      expect(host.created, hasLength(2));
    });

    test(
      'creates nothing while a surface scrolls, and resumes after',
      () async {
        scrolling.value = true;
        final warming = pool.warm(128, 2);
        await pumpEventQueue();

        expect(host.created, isEmpty);

        scrolling.value = false;
        await warming;
        expect(host.created, hasLength(2));
        expect(pool.lease(100, 100), isNotNull);
      },
    );

    test('a scroll that starts mid-warm holds the creations left', () async {
      host.holdCreations = true;
      final warming = pool.warm(128, 2);
      await pumpEventQueue();
      expect(host.created, hasLength(1));

      scrolling.value = true;
      host.completeCreations();
      await pumpEventQueue();
      expect(host.created, hasLength(1), reason: 'none created mid-scroll');

      scrolling.value = false;
      await pumpEventQueue();
      host.completeCreations();
      await warming;
      expect(host.created, hasLength(2));
    });

    test('a refused creation leaves the class short, never failed', () async {
      host.refuseCreations = true;
      await pool.warm(128, 2);

      expect(pool.lease(100, 100), isNull);
      expect(pool.bytes, 0);
    });

    test('a warm the pool outlives destroys what it created', () async {
      host.holdCreations = true;
      final warming = pool.warm(128, 1);
      await pumpEventQueue();
      pool.dispose();
      host.completeCreations();
      await warming;

      expect(host.liveIds, isEmpty);
    });
  });

  group('budget', () {
    // A 128 px texture of two buffers: 2 * 128 * 128 * 4 bytes.
    const twoBuffers128 = 2 * 128 * 128 * 4;

    setUp(() {
      pool.dispose();
      host = FakeFrameTextureHost(buffersPerTexture: 2);
      pool = FrameTexturePool(
        host: host,
        scrolling: scrolling,
        budgetBytes: twoBuffers128 + twoBuffers128 ~/ 2,
      );
    });

    test('counts every buffer of a texture, in bytes', () async {
      await pool.warm(128, 1);

      expect(pool.bytes, twoBuffers128);
    });

    test('creates no texture past it', () async {
      await pool.warm(128, 3);

      expect(host.created, hasLength(1));
      expect(pool.bytes, lessThanOrEqualTo(pool.budgetBytes));
    });

    test('leased textures count; destroyed ones go back to it', () async {
      await pool.warm(128, 1);
      final lease = pool.lease(100, 100)!;
      expect(pool.bytes, twoBuffers128);

      lease.discard();
      expect(pool.bytes, 0);
      await pool.warm(64, 1);
      expect(pool.bytes, 2 * 64 * 64 * 4);
      pool.releaseIdle();
      expect(pool.bytes, 0);
    });

    test('a budget below the smallest texture is an error', () {
      expect(
        () => FrameTexturePool(host: host, budgetBytes: 2 * 64 * 64 * 4 - 1),
        throwsArgumentError,
      );
    });
  });
}
