import 'package:chat_scroll_view_example/src/app/demo_chrome_strings.dart';
import 'package:chat_scroll_view_example/src/features/chat/outbox/demo_upload_transport.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_bytes_cache/http_bytes_cache.dart';
import 'package:mpx/mpx.dart';
import 'package:mpx_core/mpx_core.dart';
import 'package:mpx_transfer/mpx_transfer.dart';

/// The demo's transfer engine: one `Transfers` for the app, its entries in
/// the bytes store keyed as the media stack keys them, the platform's
/// system envelope with the demo's strings, and the uploads going to the
/// transports it is given.
abstract final class DemoTransfers {
  /// Opens the engine over [store], with its journal in [directory] (in
  /// memory without one), told of the app's visibility by [lifecycle];
  /// [online] is the device's connectivity now, which [followNetwork]
  /// keeps feeding.
  static Future<Transfers> open({
    required PlaybackLifecycleSource lifecycle,
    required List<UploadTransport> transports,
    required bool online,
    IBytesStore? store,
    String? directory,
    HttpBytesClient? client,
  }) => Transfers.open(
    cache: TransferBytesCache(keyOf: MpxStack.cacheKeyOf, store: store),
    lifecycle: lifecycle,
    directory: directory,
    envelope: switch (platformEnvelope()) {
      final envelope? => TransferEnvelopeSetup(
        envelope,
        config: envelopeConfig,
      ),
      null => null,
    },
    transports: transports,
    client: client,
    online: online,
  );

  /// The development upload server, from
  /// `--dart-define=CHAT_UPLOAD_SERVER=http://<host>:8090` (the transfer
  /// package's `tool/upload_server.dart`, run on a computer on the same
  /// network); null without one.
  static Uri? get devServer =>
      switch (const String.fromEnvironment('CHAT_UPLOAD_SERVER')) {
        '' => null,
        final url => Uri.parse(url),
      };

  /// The id of the transport to [devServer].
  static const String devServerTransportId = 'devServer';

  /// The engine's upload transports: [demo] alone, or, with a [devServer],
  /// tus to that server first (a job naming no transport takes the first)
  /// over [client], with [demo] after it.
  static List<UploadTransport> transportsFor({
    required DemoUploadTransport demo,
    Uri? devServer,
    HttpBytesClient? client,
  }) => [
    if ((devServer, client) case (final server?, final client?))
      TusUploadTransport(
        id: devServerTransportId,
        endpoint: server.resolve('/tus/'),
        client: client,
        // The server names its file in a header of its own.
        remoteRef: (upload, headers) =>
            RemoteRef(headers['x-file-id'] ?? upload.pathSegments.last),
      ),
    demo,
  ];

  /// The envelope's notification, in the demo's strings.
  static final TransferEnvelopeConfig envelopeConfig = TransferEnvelopeConfig(
    title: DemoTransferStrings.envelopeTitle,
    text: DemoTransferStrings.envelopeText,
    cancelAllLabel: DemoTransferStrings.cancelAll,
    progressText: (progress) =>
        DemoTransferStrings.uploadsLeft(progress.jobs.length),
  );

  /// The platform's system envelope: Android and iOS have one; desktop and
  /// the web run every job in the process.
  static TransferEnvelope? platformEnvelope() {
    if (kIsWeb) return null;
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => AndroidTransferEnvelope(),
      TargetPlatform.iOS => IosTransferEnvelope(),
      TargetPlatform.macOS ||
      TargetPlatform.windows ||
      TargetPlatform.linux ||
      TargetPlatform.fuchsia => null,
    };
  }

  /// Feeds [network] into [transfers] as its connectivity from now on,
  /// offline whatever the device says while [cut] is on; the returned
  /// function stops it.
  static VoidCallback followNetwork(
    Transfers transfers,
    ValueListenable<NetworkClass> network, {
    ValueListenable<bool>? cut,
  }) {
    bool onlineNow() =>
        network.value != NetworkClass.none && !(cut?.value ?? false);
    var online = onlineNow();
    void feed() {
      final now = onlineNow();
      if (now == online) return;
      online = now;
      transfers.connectivityChanged(online: now);
    }

    network.addListener(feed);
    cut?.addListener(feed);
    return () {
      network.removeListener(feed);
      cut?.removeListener(feed);
    };
  }
}

/// The debug panel's switch that cuts the transfer engine's network: while
/// [value] is true the engine reads offline (through
/// [DemoTransfers.followNetwork]) and every request through [middleware]
/// fails as a dropped connection would.
///
/// The device keeps its network; only the engine's requests fail, so a
/// check can cut the network in the middle of an upload and give it back.
final class DemoNetworkCut extends ValueNotifier<bool> {
  /// A switch, off.
  DemoNetworkCut() : super(false);

  /// Fails every request while the network is cut.
  HttpBytesMiddleware get middleware =>
      (inner) => (request, context) {
        if (value) throw http.ClientException('network cut (debug panel)');
        return inner(request, context);
      };
}
