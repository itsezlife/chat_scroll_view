import 'dart:io';

import 'package:chat_scroll_view_example/src/features/chat/outbox/demo_transfers.dart';
import 'package:chat_scroll_view_example/src/features/chat/outbox/demo_upload_transport.dart';
import 'package:chat_scroll_view_example/src/features/chat/outbox/outbox_debug_actions.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http_bytes_cache/http_bytes_cache.dart';
import 'package:mpx/mpx.dart';
import 'package:mpx_core/testing.dart';
import 'package:mpx_transfer/mpx_transfer.dart';

void main() {
  late Transfers transfers;
  late ValueNotifier<NetworkClass> network;
  late DemoNetworkCut cut;
  late DemoUploadTransport transport;
  late VoidCallback stop;

  setUp(() async {
    final directory = Directory.systemTemp.createTempSync('demo_transfers_');
    addTearDown(() => directory.deleteSync(recursive: true));
    transport = DemoUploadTransport(latency: Duration.zero);
    transfers = await Transfers.open(
      cache: const TransferBytesCache(keyOf: MpxStack.cacheKeyOf),
      directory: directory.path,
      lifecycle: ManualPlaybackLifecycleSource(
        initial: AppLifecycleState.resumed,
      ),
      transports: [transport],
      online: true,
    );
    network = ValueNotifier(NetworkClass.unmetered);
    cut = DemoNetworkCut();
    stop = DemoTransfers.followNetwork(transfers, network, cut: cut);
  });

  tearDown(() async {
    stop();
    cut.dispose();
    network.dispose();
    await transfers.dispose();
  });

  test('a cut reads offline whatever the device says, and its end reads the '
      'device again', () {
    cut.value = true;
    expect(transfers.debugSnapshot().online, isFalse);

    network
      ..value = NetworkClass.none
      ..value = NetworkClass.metered;
    expect(transfers.debugSnapshot().online, isFalse, reason: 'still cut');

    cut.value = false;
    expect(transfers.debugSnapshot().online, isTrue);

    network.value = NetworkClass.none;
    expect(transfers.debugSnapshot().online, isFalse);
  });

  test('the cut fails every request through its middleware, as a dropped '
      'connection would', () async {
    final client = HttpBytesClient(middlewares: [cut.middleware]);
    addTearDown(client.close);
    cut.value = true;

    await expectLater(
      client.send(
        HttpBytesRequest(
          http.Request('GET', Uri.parse('http://localhost:1/x')),
        ),
      ),
      throwsA(isA<http.ClientException>()),
    );
  });

  test('uploads go to the in-process transport unless a dev server is named, '
      'which then comes first over tus', () {
    final client = HttpBytesClient();
    addTearDown(client.close);

    expect(DemoTransfers.transportsFor(demo: transport), [transport]);

    final [first, second] = DemoTransfers.transportsFor(
      demo: transport,
      devServer: Uri.parse('http://192.168.1.5:8090'),
      client: client,
    );
    expect(first, isA<TusUploadTransport>());
    expect(first.id, DemoTransfers.devServerTransportId);
    expect(
      (first as TusUploadTransport).endpoint,
      Uri.parse('http://192.168.1.5:8090/tus/'),
    );
    expect(second, same(transport));
  });

  test("the engine hooks cut the in-process transport and the engine's "
      'connectivity, and act out a system interruption', () {
    final hooks = TransferDebugHooks.engine(
      transfers,
      cut: cut,
      transport: transport,
    );

    hooks.cutNetwork(cut: true);
    expect(transport.offline, isTrue);
    expect(hooks.snapshot()?.online, isFalse);

    hooks.cutNetwork(cut: false);
    expect(transport.offline, isFalse);
    expect(hooks.snapshot()?.online, isTrue);

    expect(hooks.simulateSystemInterruption(), 0, reason: 'no jobs');
  });
}
