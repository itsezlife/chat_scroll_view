import 'package:chat_outbox/src/message/outgoing_status.dart';
import 'package:chat_outbox/src/outbox/publish_rejection_codec.dart';
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
      status: OutgoingStatus.failed(failureOf(reason)),
      stage: stage,
    ),
    PublishJobState$Completed() => (
      status: const OutgoingStatus.sent(),
      stage: null,
    ),
  };

  /// The closed failure a job failed for [reason] reads as.
  ///
  /// The chat publisher's codes (`PublishRejectionCodec`, all but
  /// `tooLarge` under the `chat.` prefix) are its rejections and denials,
  /// and `tooLarge` (a preparer's or a publisher's code) is too large. Of
  /// the engine's open set of reasons, the network and a lost source are
  /// their own failures; every other one, the engine's codes for its own
  /// faults included, is unknown. A server's rejection code never reaches
  /// this space bare, so one that spells an engine reason stays a
  /// rejection.
  static OutgoingFailure failureOf(PublishFailureReason reason) =>
      switch (reason.code) {
        final code when PublishRejectionCodec.owns(code) => _publisherFailureOf(
          code,
        ),
        _network => const OutgoingFailure.network(),
        _sourceLost => const OutgoingFailure.sourceLost(),
        _ => const OutgoingFailure.unknown(),
      };

  // The chat publisher's own codes: a rejection, a denial, or a code this
  // build cannot read (a denial of an action it no longer knows).
  static OutgoingFailure _publisherFailureOf(String code) {
    try {
      return const PublishRejectionCodec().decode(code);
    } on FormatException {
      return const OutgoingFailure.unknown();
    }
  }

  // The upload failure kinds' names (`TransferFailureKind`).
  static const _network = 'network';
  static const _sourceLost = 'sourceLost';

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
