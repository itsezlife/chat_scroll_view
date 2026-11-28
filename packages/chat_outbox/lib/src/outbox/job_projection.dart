import 'package:chat_outbox/src/message/outgoing_status.dart';
import 'package:meta/meta.dart';
import 'package:mpx_transfer/mpx_transfer.dart';

/// A publish job's state read as an outgoing message's status: the
/// projection the outbox keeps instead of a store.
///
/// | Job state | Status | Stage |
/// | --- | --- | --- |
/// | `preparing` | `preparing` | prepare |
/// | `uploading` | `uploading` | upload |
/// | `publishing` | `publishing` | publish |
/// | `completed` | `sent` | none |
/// | `failed(stage, reason)` | `failed`, the reason read by [failureOf] | the failed stage |
/// | `awaitingPublisher`, `paused(any reason)` | by stage: `uploading` while an item is not uploaded, else `publishing` | the same |
/// | `awaitingOwner` | unchanged: the owner decides what the message becomes | none |
///
/// A paused or waiting job keeps reading as sending, so a system
/// interruption or a missing publisher never shows a message as stuck in a
/// state of its own. `cancelled` never comes from a job: the engine removes
/// a cancelled job, and the outbox, which cancelled it, reports it.
@internal
abstract final class JobProjection {
  /// The status and stage of [job], whose message reads [current] now.
  static ({OutgoingStatus status, PublishStage? stage}) of(
    PublishJobSnapshot job,
    OutgoingStatus current,
  ) => switch (job.state) {
    PublishJobState$Preparing() => (
      status: const OutgoingStatus.preparing(),
      stage: PublishStage.prepare,
    ),
    PublishJobState$Uploading() => (
      status: const OutgoingStatus.uploading(),
      stage: PublishStage.upload,
    ),
    PublishJobState$Publishing() => (
      status: const OutgoingStatus.publishing(),
      stage: PublishStage.publish,
    ),
    PublishJobState$AwaitingPublisher() ||
    PublishJobState$Paused() => _byStage(job),
    PublishJobState$AwaitingOwner() => (status: current, stage: null),
    PublishJobState$Failed(:final stage, :final reason) => (
      status: OutgoingStatus.failed(failureOf(stage, reason)),
      stage: stage,
    ),
    PublishJobState$Completed() => (
      status: const OutgoingStatus.sent(),
      stage: null,
    ),
  };

  /// The closed failure a job failed at [stage] for [reason] reads as.
  ///
  /// The engine's reasons are an open set of codes: the network and a lost
  /// source are their own failures, `tooLarge` (a preparer's or a
  /// publisher's code) is too large, and any other reason the publish stage
  /// gives is the publisher's rejection, kept as its code. The engine's own
  /// codes for its faults, and any other code at an earlier stage, are
  /// unknown.
  static OutgoingFailure failureOf(
    PublishStage stage,
    PublishFailureReason reason,
  ) => switch (reason.code) {
    _network => const OutgoingFailure.network(),
    _sourceLost => const OutgoingFailure.sourceLost(),
    _tooLarge => const OutgoingFailure.tooLarge(),
    final code when _engineCodes.contains(code) =>
      const OutgoingFailure.unknown(),
    final code when stage == PublishStage.publish => OutgoingFailure.rejected(
      code,
    ),
    _ => const OutgoingFailure.unknown(),
  };

  // The upload failure kinds' names (`TransferFailureKind`) and the code a
  // preparer or publisher gives for content over the server's size.
  static const _network = 'network';
  static const _sourceLost = 'sourceLost';
  static const _tooLarge = 'tooLarge';

  /// The engine's codes for its own faults and the upload failure kinds
  /// that are not the user's to read: never a publisher's rejection.
  static final Set<String> _engineCodes = {
    PublishFailureReason.noPreparation,
    PublishFailureReason.cancelled,
    PublishFailureReason.unexpected,
    PublishFailureReason.unknownTransport,
    PublishFailureReason.sourceUnwritable,
    PublishFailureReason.thumbnailUnreadable,
    PublishFailureReason.transport,
    PublishFailureReason.publisherError,
    PublishFailureReason.reuploadRefused,
    TransferFailureKind.server.name,
    TransferFailureKind.local.name,
  };

  // A paused or waiting job has no stage of its own: its items tell it.
  static ({OutgoingStatus status, PublishStage? stage}) _byStage(
    PublishJobSnapshot job,
  ) {
    final uploading = job.items.any(
      (item) => switch (item.state) {
        PublishItemState$Uploaded() || PublishItemState$Removed() => false,
        _ => true,
      },
    );
    return uploading
        ? (status: const OutgoingStatus.uploading(), stage: PublishStage.upload)
        : (
            status: const OutgoingStatus.publishing(),
            stage: PublishStage.publish,
          );
  }
}
