import 'package:catalog_assets/src/texture/frame_texture_host.dart';
import 'package:flutter_test/flutter_test.dart';

/// The behaviour every [FrameTextureHost] shares, run over the fake and over
/// each platform host alike (the platform hosts on a device).
///
/// A host that cannot create textures where the suite runs (a device without
/// the producer) fails the creation tests rather than skipping them: the
/// failure rule (ADR 043) covers a refusal at run time, but a host under test
/// that never creates one tests nothing.
abstract final class FrameTextureHostContract {
  /// Registers the contract's tests; [create] builds a fresh host for each.
  static void run(FrameTextureHost Function() create) {
    group('FrameTextureHost contract', () {
      late FrameTextureHost host;
      late List<int> made;

      setUp(() {
        host = create();
        made = [];
      });

      tearDown(() {
        made.forEach(host.destroy);
      });

      Future<int> texture(int width, int height) async {
        final id = await host.create(width, height);
        expect(id, isNotNull, reason: 'the host refused a texture');
        made.add(id!);
        return id;
      }

      test('a texture holds at least one buffer', () {
        expect(host.buffersPerTexture, greaterThanOrEqualTo(1));
      });

      test('live textures have distinct ids', () async {
        final first = await texture(64, 64);
        final second = await texture(64, 64);

        expect(first, isNot(second));
      });

      test(
        "a lock gives the texture's size, a stride and the host's format",
        () async {
          final id = await texture(128, 64);

          final target = host.lock(id);

          expect(target, isNotNull);
          expect(target!.width, 128);
          expect(target.height, 64);
          expect(target.rowStride, greaterThanOrEqualTo(128 * 4));
          expect(target.format, host.format);
          expect(target.address, isNot(0));
          host.post(id);
        },
      );

      test('a locked texture does not lock again until it is posted', () async {
        final id = await texture(64, 64);
        host.lock(id);

        expect(host.lock(id), isNull);
        host.post(id);
        expect(host.lock(id), isNotNull);
        host.post(id);
      });

      test('a post without a lock does nothing', () async {
        final id = await texture(64, 64);

        host
          ..post(id)
          ..post(id);

        expect(host.lock(id), isNotNull);
        host.post(id);
      });

      test(
        'an unknown id neither locks, posts nor destroys anything',
        () async {
          final id = await texture(64, 64);
          final unknown = id + 1000003;

          expect(host.lock(unknown), isNull);
          host
            ..post(unknown)
            ..destroy(unknown);
          expect(host.lock(id), isNotNull, reason: 'the live one is untouched');
          host.post(id);
        },
      );

      test(
        'a destroyed texture never locks again; destroy is idempotent',
        () async {
          final id = await texture(64, 64);

          host
            ..destroy(id)
            ..destroy(id);

          expect(host.lock(id), isNull);
        },
      );
    });
  }
}
