import 'package:mpx_transfer/mpx_transfer.dart';

/// The demo's upload transport: a remote end in the process, which takes
/// every part after [latency] and never reads its bytes, so the transfer
/// engine runs its real parts, budgets, retries and journal against it.
///
/// Its switches: [offline] fails every call as a transient network failure
/// (the engine waits and tries again), and [failNext] fails that many
/// calls for good (the upload, and its message, fail).
///
/// Example only. A development server over the network takes its place
/// once one is chosen; this one keeps the demo working with no network.
final class DemoUploadTransport implements UploadTransport {
  /// A transport that answers each call after [latency], in parts of
  /// [partBytes].
  DemoUploadTransport({
    this.latency = const Duration(milliseconds: 300),
    int partBytes = 256 * 1024,
  }) : capabilities = UploadCapabilities(
         partSize: (_) => partBytes,
         resume: const UploadResume.unlimited(),
         reuse: const UploadReuse.lifetime(Duration(days: 1)),
       );

  /// How long each call takes.
  Duration latency;

  /// Whether every call fails as the network being down.
  bool offline = false;

  /// How many of the next calls fail for good.
  int failNext = 0;

  @override
  String get id => 'demo';

  @override
  final UploadCapabilities capabilities;

  int _$uploads = 0;
  final Set<String> _$tokens = {};

  @override
  Future<UploadSession> open(UploadInfo info, {String? resumeToken}) async {
    await _call();
    if (resumeToken != null && _$tokens.contains(resumeToken)) {
      return _DemoUploadSession(this, resumeToken, resumed: true);
    }
    final token = 'demo-${_$uploads++}';
    _$tokens.add(token);
    return _DemoUploadSession(this, token, resumed: false);
  }

  Future<void> _call() async {
    await Future<void>.delayed(latency);
    if (offline) {
      throw const UploadTransportException(
        'offline',
        kind: TransferFailureKind.network,
        transient: true,
      );
    }
    if (failNext > 0) {
      failNext--;
      throw const UploadTransportException('demo.failed');
    }
  }
}

final class _DemoUploadSession implements UploadSession {
  _DemoUploadSession(
    this._transport,
    this.resumeToken, {
    required this.resumed,
  });

  final DemoUploadTransport _transport;

  @override
  final String resumeToken;

  @override
  final bool resumed;

  @override
  DateTime? get resumeExpiresAt => null;

  @override
  Future<UploadPartAck> sendPart(
    int index,
    int offset,
    UploadPartBody bytes, {
    required bool last,
  }) async {
    await _transport._call();
    return UploadPartAck(receipt: '$resumeToken/$index');
  }

  @override
  Future<RemoteRef> finish(int finalSize, List<UploadPartAck> parts) async {
    await _transport._call();
    return RemoteRef(resumeToken, attributes: {'size': '$finalSize'});
  }
}
