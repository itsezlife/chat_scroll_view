import 'package:chat_scroll_view_example/src/features/chat/outbox/demo_upload_transport.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpx_transfer/mpx_transfer.dart';
import 'package:mpx_transfer/testing.dart';

void main() {
  UploadTransportContract.run(
    'DemoUploadTransport',
    transport: () => DemoUploadTransport(latency: Duration.zero),
  );

  const info = UploadInfo(size: 10, partSize: 10, partCount: 1);

  test('each call takes the latency', () {
    fakeAsync((async) {
      final transport = DemoUploadTransport(
        latency: const Duration(milliseconds: 300),
      );
      UploadSession? session;
      transport.open(info).then((s) => session = s);

      async.elapse(const Duration(milliseconds: 299));
      expect(session, isNull);
      async.elapse(const Duration(milliseconds: 1));
      expect(session, isNotNull);
    });
  });

  test('offline, every call fails as a transient network failure until it is '
      'back', () async {
    final transport = DemoUploadTransport(latency: Duration.zero)
      ..offline = true;

    await expectLater(
      transport.open(info),
      throwsA(
        isA<UploadTransportException>()
            .having((e) => e.transient, 'transient', isTrue)
            .having((e) => e.kind, 'kind', TransferFailureKind.network),
      ),
    );
    transport.offline = false;
    expect(await transport.open(info), isA<UploadSession>());
  });

  test('failNext fails that many calls, for good', () async {
    final transport = DemoUploadTransport(latency: Duration.zero)..failNext = 1;

    await expectLater(
      transport.open(info),
      throwsA(
        isA<UploadTransportException>().having(
          (e) => e.transient,
          'transient',
          isFalse,
        ),
      ),
    );
    expect(await transport.open(info), isA<UploadSession>());
  });
}
