import 'dart:typed_data';

import 'package:mpx_transfer/mpx_transfer.dart';

/// What the outbox uses of the transfer engine: making a publish job,
/// watching a chat's jobs and registering the chat's publisher. The host passes [OutboxTransfers.of] its one
/// `Transfers` facade.
///
/// The outbox reaches the engine through this seam rather than through
/// `Transfers` itself because `Transfers` and its `PublishJob` handles are
/// final and built only by the engine: a test of the outbox, or of a host
/// that drives one, could not stand in for them. The seam names only what
/// the outbox calls, and grows with it.
abstract interface class OutboxTransfers {
  /// The seam over [transfers], the host's facade.
  factory OutboxTransfers.of(Transfers transfers) = _OutboxTransfers$Engine;

  /// Makes a publish job for [request] and answers its id.
  ///
  /// Throws as `Transfers.publish` does: for an item that needs preparation
  /// on a facade without it, an item id given twice, or a facade that runs
  /// no uploads.
  PublishJobId publish(PublishRequest request);

  /// Snapshots of every publish job [filter] passes, oldest first: the
  /// current list on listen, then the list again whenever one of its jobs
  /// changes, as `Transfers.watchJobs` gives them.
  Stream<List<PublishJobSnapshot>> watchJobs(PublishJobFilter filter);

  /// Registers [publisher] under [id], replacing any registered before; the
  /// jobs waiting for it publish, as `Transfers.registerPublisher` does.
  void registerPublisher(String id, Publisher publisher);

  /// The payload job [id] was made with, as its journal holds it; null for
  /// a job the engine no longer has.
  ///
  /// The outbox reads it after a restart, when the job's message is known
  /// only from the journal: it decodes the payload into the host's model to
  /// build the message's row again.
  Uint8List? payloadOf(PublishJobId id);
}

final class _OutboxTransfers$Engine implements OutboxTransfers {
  _OutboxTransfers$Engine(this._transfers);

  final Transfers _transfers;

  @override
  PublishJobId publish(PublishRequest request) =>
      _transfers.publish(request).id;

  @override
  Stream<List<PublishJobSnapshot>> watchJobs(PublishJobFilter filter) =>
      _transfers.watchJobs(filter);

  @override
  void registerPublisher(String id, Publisher publisher) =>
      _transfers.registerPublisher(id, publisher);

  @override
  Uint8List? payloadOf(PublishJobId id) => _transfers.publishJob(id)?.payload;
}
