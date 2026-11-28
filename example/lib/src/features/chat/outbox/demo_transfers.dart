import 'package:chat_scroll_view_example/src/app/demo_chrome_strings.dart';
import 'package:flutter/foundation.dart';
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

  /// Feeds [network] into [transfers] as its connectivity from now on; the
  /// returned function stops it.
  static VoidCallback followNetwork(
    Transfers transfers,
    ValueListenable<NetworkClass> network,
  ) {
    var online = network.value != NetworkClass.none;
    void feed() {
      final now = network.value != NetworkClass.none;
      if (now == online) return;
      online = now;
      transfers.connectivityChanged(online: now);
    }

    network.addListener(feed);
    return () => network.removeListener(feed);
  }
}
