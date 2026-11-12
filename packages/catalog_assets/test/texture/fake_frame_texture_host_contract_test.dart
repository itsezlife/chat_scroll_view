import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/testing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  FrameTextureHostContract.run(FakeFrameTextureHost.new);
  FrameTextureHostContract.run(
    () => FakeFrameTextureHost(
      format: FrameTextureFormat.bgra8888,
      buffersPerTexture: 3,
      rowPadding: 32,
    ),
  );

  group('FakeFrameTextureHost', () {
    test('backs a lock with plain memory a test can read', () async {
      final host = FakeFrameTextureHost(rowPadding: 8);
      final id = (await host.create(2, 3))!;
      final target = host.lock(id)!;

      expect(target.rowStride, 2 * 4 + 8);
      expect(host.pixelsOf(id), hasLength(3 * (2 * 4 + 8)));
      host.post(id);
      expect(host.posts, [id]);
    });

    test('refuses as a platform would, on demand', () async {
      final host = FakeFrameTextureHost()..refuseCreations = true;
      expect(await host.create(64, 64), isNull);

      host.refuseCreations = false;
      final id = (await host.create(64, 64))!;
      host.refuseLocks = true;
      expect(host.lock(id), isNull);
    });
  });
}
