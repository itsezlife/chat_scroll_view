import 'package:attach_model/attach_model.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:test/test.dart';

void main() {
  late FakeKeyValueStore storage;

  setUp(() => storage = FakeKeyValueStore());

  SendOptionStore storeFor(AttachPolicy policy) =>
      SendOptionStore(storage, policy: policy);

  test(
    'Android keeps high quality and the video preset per offered count',
    () async {
      final store = storeFor(const AttachPolicy.android());
      await store.save(
        const SendOptions(highQuality: true, videoPreset: 640, grouped: false),
        offeredPresets: 3,
      );
      await store.save(
        const SendOptions(highQuality: true, videoPreset: 432),
        offeredPresets: 2,
      );

      final three = await storeFor(
        const AttachPolicy.android(),
      ).restore(const SendOptions(), offeredPresets: 3);
      final two = await storeFor(
        const AttachPolicy.android(),
      ).restore(const SendOptions(), offeredPresets: 2);
      final four = await storeFor(
        const AttachPolicy.android(),
      ).restore(const SendOptions(), offeredPresets: 4);

      expect(three, const SendOptions(highQuality: true, videoPreset: 640));
      expect(two, const SendOptions(highQuality: true, videoPreset: 432));
      expect(four, const SendOptions(highQuality: true));
    },
  );

  test('iOS keeps high quality and one preferred preset', () async {
    await storeFor(const AttachPolicy.ios()).save(
      const SendOptions(highQuality: true, videoPreset: 1280, asFiles: true),
    );

    final restored = await storeFor(
      const AttachPolicy.ios(),
    ).restore(const SendOptions(), offeredPresets: 2);

    expect(restored, const SendOptions(highQuality: true, videoPreset: 1280));
  });

  test('desktop writes nothing without Remember', () async {
    await storeFor(
      const AttachPolicy.desktop(),
    ).save(const SendOptions(grouped: false, asFiles: true, highQuality: true));

    expect(storage.writeCount, 0);
    expect(
      await storeFor(const AttachPolicy.desktop()).restore(const SendOptions()),
      const SendOptions(),
    );
  });

  test(
    'desktop keeps group, as files and large photos when remembered',
    () async {
      await storeFor(const AttachPolicy.desktop()).save(
        const SendOptions(
          grouped: false,
          asFiles: true,
          highQuality: true,
          silent: true,
          videoPreset: 720,
        ),
        remember: true,
      );

      expect(
        await storeFor(
          const AttachPolicy.desktop(),
        ).restore(const SendOptions()),
        const SendOptions(grouped: false, asFiles: true, highQuality: true),
      );
    },
  );

  test('the web keeps nothing', () async {
    await storeFor(const AttachPolicy.web()).save(
      const SendOptions(grouped: false, asFiles: true, highQuality: true),
      remember: true,
    );

    expect(storage.writeCount, 0);
  });

  test('a value of an unknown version is ignored', () async {
    await storage.write(
      SendOptionStore.namespace,
      'high_quality',
      const StoredValue('true', version: 99),
    );

    expect(
      await storeFor(const AttachPolicy.ios()).restore(const SendOptions()),
      const SendOptions(),
    );
  });
}
