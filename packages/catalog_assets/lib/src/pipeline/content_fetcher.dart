import 'dart:typed_data';

import 'package:catalog_assets/src/asset/asset_producer.dart';
import 'package:catalog_assets/src/pipeline/cancellation_token.dart';
import 'package:content_model/content_model.dart';
import 'package:meta/meta.dart';

/// Which bytes of a piece of content a fetch is for.
enum FetchPart {
  /// The stand-in named by `ContentDescriptor.thumbnail`: small, shown while
  /// the content loads. Only requested for a descriptor that has one.
  thumbnail,

  /// The content itself.
  content,
}

/// What a [ContentFetcher] is asked for.
@immutable
final class FetchRequest {
  /// Creates a request for [part] of [descriptor].
  const FetchRequest({
    required this.descriptor,
    required this.part,
    required this.priority,
    required this.cancellation,
  });

  /// What is known about the content. For [FetchPart.thumbnail] its
  /// `thumbnail` is set.
  final ContentDescriptor descriptor;

  /// Which bytes.
  final FetchPart part;

  /// How urgent the fetch is, for a fetcher that queues its own network
  /// work. It does not change while the fetch runs.
  final AssetPriority priority;

  /// Cancelled when nobody wants the result any more.
  final CancellationToken cancellation;
}

/// What a fetch produced.
///
/// Either the bytes in memory or a file the host's disk tier holds; a decoder
/// takes whichever suits its codec (a video decoder wants the file).
@immutable
sealed class FetchedContent {
  const FetchedContent();

  /// Content held in memory.
  const factory FetchedContent.bytes(Uint8List bytes) = FetchedBytes;

  /// Content in a file at [path].
  const factory FetchedContent.file(String path) = FetchedFile;
}

/// [FetchedContent] held in memory.
final class FetchedBytes extends FetchedContent {
  /// Creates content from [bytes], which the fetcher no longer changes.
  const FetchedBytes(this.bytes);

  /// The encoded data.
  final Uint8List bytes;
}

/// [FetchedContent] in a file.
///
/// The file belongs to the host's disk tier: the pipeline and the decoders
/// read it and never delete or move it.
final class FetchedFile extends FetchedContent {
  /// Creates content read from [path].
  const FetchedFile(this.path);

  /// Where the encoded data is.
  final String path;
}

/// Why a fetch failed, as the pipeline needs to know it.
///
/// The [kind] tells whether the host's connectivity-restored signal can help.
/// The pipeline never shows a failure: the entry keeps its stage and the
/// attempt is repeated on a re-attach, on `AssetBinding.retry`, and, for a
/// [AssetFailureKind.transient] one, when connectivity returns.
final class FetchFailure implements Exception {
  /// Creates a failure of class [kind] explained by [message].
  const FetchFailure(this.kind, this.message, [this.cause]);

  /// Offline, timed out or a server that is busy: worth repeating later.
  const FetchFailure.transient(String message, [Object? cause])
    : this(AssetFailureKind.transient, message, cause);

  /// Missing or forbidden content: repeating it unchanged will not help.
  const FetchFailure.permanent(String message, [Object? cause])
    : this(AssetFailureKind.permanent, message, cause);

  /// Whether connectivity can fix it.
  final AssetFailureKind kind;

  /// What went wrong, for logs.
  final String message;

  /// The underlying error, if any.
  final Object? cause;

  @override
  String toString() => 'FetchFailure(${kind.name}): $message';
}

/// Gets the encoded bytes of content, from wherever the host keeps them.
///
/// The host implements it, because only the host knows the network, the way
/// file references expire and are refreshed, and the disk tier below it. The
/// pipeline asks for every part it needs and never caches bytes itself.
///
/// ## Contract
///
/// - [fetch] runs on the UI isolate and returns at once; the work may happen
///   anywhere. The future completes on the UI isolate.
/// - It completes with the content, or fails with a [FetchFailure]. Any other
///   error is treated as a transient failure.
/// - Content that does not exist is a permanent [FetchFailure]; no network,
///   a timeout or a busy server is a transient one.
/// - A fetch for a [FetchPart.thumbnail] returns the stand-in, for a
///   [FetchPart.content] the content, even when the same bytes would do.
/// - When `FetchRequest.cancellation` is cancelled the fetcher stops its work
///   as soon as it can and settles the future: with whatever it already has,
///   or with a failure. It never leaves the future pending.
/// - It may run many fetches at once; the pipeline's caps bound how many it is
///   given.
abstract interface class ContentFetcher {
  /// Gets [FetchRequest.part] of [FetchRequest.descriptor].
  Future<FetchedContent> fetch(FetchRequest request);
}
